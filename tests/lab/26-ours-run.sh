#!/bin/bash
# Restore our modules and repeat the same questions on the same filesystem and
# the same boot, so the two sides differ only in which modules are installed.
set -u
BIG='0x200000401:0x7:0x0'
cd ~
sudo umount /mnt/testfs 2>/dev/null
for i in 0 1 2 3; do sudo umount /mnt/testfs-ost$i 2>/dev/null; done
sudo umount /mnt/testfs-mdt0 2>/dev/null
sudo lustre_rmmod 2>/dev/null
sleep 2
cd ~/lustre-release
sudo make install > /tmp/o-install.log 2>&1 || { tail -15 /tmp/o-install.log; exit 1; }
sudo depmod -a
sudo modprobe lustre && sudo modprobe osd_ldiskfs
modinfo osd_ldiskfs | grep -E '^version'
echo "  LFU parms back: $(modinfo osd_ldiskfs | grep -c lfu_blockparse)"
sudo lnetctl lnet configure 2>/dev/null || true
sudo lnetctl net add --net tcp0 --if $(ip -o -4 route show to default | awk '{print $5}') 2>/dev/null || true
sudo mount -t lustre -o loop /lustre/mdt.img /mnt/testfs-mdt0
for i in 0 1 2 3; do sudo mount -t lustre -o loop /lustre/ost$i.img /mnt/testfs-ost$i; done
sleep 4

cd ~/lfu
ring() { sudo rmmod lfu_ring 2>/dev/null; sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd; }

echo
echo "=== OURS: the same size questions on the same MDT ==="
ring; printf '    --size +1G      -> '; sudo timeout 600 build/lfu-scan-kmdt --size +1G /dev/lfu_scan 2>/dev/null | grep -c '^\['
ring; printf '    --size +100M    -> '; sudo timeout 600 build/lfu-scan-kmdt --size +100M /dev/lfu_scan 2>/dev/null | grep -c '^\['
ring; printf '    --size -1M      -> '; sudo timeout 600 build/lfu-scan-kmdt --size -1M /dev/lfu_scan 2>/dev/null | grep -c '^\['
echo "    is the 1.5 GiB file wrongly in '--size -1M'?"
ring; sudo timeout 600 build/lfu-scan-kmdt --size -1M /dev/lfu_scan 2>/dev/null | grep -cF "$BIG" | sed 's/^/      matches: /'
echo "    and what does ours report for it under a size filter?"
ring; sudo timeout 600 build/lfu-scan-kmdt --size +1G /dev/lfu_scan 2>/dev/null | grep -F "$BIG" | sed 's/^/      /'

echo
echo "=== OURS: rates on this boot, objects visited per second, medians of 3 ==="
rate() {   # rate <label> <args...>
	local label="$1"; shift
	local rs=""
	for p in 1 2 3; do
		ring
		local r=$(sudo timeout 900 build/lfu-scan-kmdt -q "$@" /dev/lfu_scan 2>&1 |
			  grep -oE 'rate *: *[0-9]+' | grep -oE '[0-9]+$')
		rs="$rs ${r:-0}"
	done
	local med=$(echo $rs | tr ' ' '\n' | sort -n | sed -n 2p)
	printf '    %-38s %-9s (%s)\n' "$label" "$med" "$rs"
}
rate "no filter"
rate "--uid 4242            (rejects all)"  --uid 4242
rate "--size +1G            (tier 1, SOM)"  --size +1G
rate "--mtime +365d         (rejects all)"  --mtime +365d
sudo rmmod lfu_ring 2>/dev/null
echo "OURS DONE"
