#!/bin/bash
# Ground truth, from the device rather than from either scanner: what size does
# the MDT inode of a 1.5 GiB striped file actually hold?  Their --size filter on
# an MDT reads exactly this number (dt_attr_get -> la_size).
set -e
cd ~/lfu
echo "=== the client's view ==="
sudo stat -c 'big1: size=%s blocks=%b' /mnt/testfs/shapes/big1
sudo lfs path2fid /mnt/testfs/shapes/big1

echo
echo "=== the MDT inode's own view, via our scanner with NO filter ==="
echo "    (no filter => no SOM read => size= is the MDT inode's i_size)"
sudo rmmod lfu_ring 2>/dev/null || true
sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
sudo timeout 300 build/lfu-scan-kmdt /dev/lfu_scan 2>/dev/null |
	grep -E '0x200000401:0x(7|5|9|b):0x0' | sed 's/^/    /'
sudo rmmod lfu_ring 2>/dev/null || true

echo
echo "=== and with a size filter, which reads trusted.som ==="
sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
sudo timeout 300 build/lfu-scan-kmdt --size +1G /dev/lfu_scan 2>/dev/null | sed 's/^/    /'
sudo rmmod lfu_ring 2>/dev/null || true

echo
echo "=== the same inode read straight off the device with debugfs ==="
INO=$(sudo build/lfu-scan-ldiskfs --size +1G /lustre/mdt.img 2>/dev/null | grep -oE 'ino=[0-9]+' | cut -d= -f2)
echo "    inode = $INO"
sudo debugfs -R "stat <$INO>" /lustre/mdt.img 2>/dev/null | grep -iE '^Size:|^Inode:|Size of extra|Blockcount' | sed 's/^/    /'
echo "    --- and its trusted.som, which is where the real size lives ---"
sudo debugfs -R "ea_get -V <$INO> trusted.som" /lustre/mdt.img 2>/dev/null | tail -2 | od -An -tx1 | head -3 | sed 's/^/    /'
python3 - <<'PY'
print("    lsa_size is bytes 8..15 of that value, little-endian")
PY
