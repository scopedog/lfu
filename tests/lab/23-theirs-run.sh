#!/bin/bash
# Their round: install the LU-20591 modules + utils over ours, remount the SAME
# filesystem, and exercise 68020's filter.  Two questions:
#   (a) what does --size mean on an MDT, where the inode holds 0 for a striped
#       file and the real size is in trusted.som;
#   (b) does filtering save them scan work, or only copy_to_user.
set -u
cd ~
echo "=== unmount ==="
sudo umount /mnt/testfs 2>/dev/null
for i in 0 1 2 3; do sudo umount /mnt/testfs-ost$i 2>/dev/null; done
sudo umount /mnt/testfs-mdt0 2>/dev/null
sudo rmmod lfu_ring 2>/dev/null
sudo lustre_rmmod 2>/dev/null
sleep 2

echo "=== install THEIRS ==="
cd ~/lustre-xiong
sudo make install > /tmp/x-install.log 2>&1 || { tail -15 /tmp/x-install.log; exit 1; }
sudo depmod -a
sudo modprobe lustre || { echo "modprobe failed"; dmesg | tail -5; exit 1; }
sudo modprobe osd_ldiskfs
modinfo osd_ldiskfs | grep -E '^filename|^version'
echo "  LFU parms (should be ABSENT now): $(modinfo osd_ldiskfs | grep -c lfu_blockparse)"
which lctl; lctl --version 2>/dev/null | head -1

echo "=== remount the same filesystem ==="
sudo lnetctl lnet configure 2>/dev/null || true
sudo lnetctl net add --net tcp0 --if $(ip -o -4 route show to default | awk '{print $5}') 2>/dev/null || true
NID=$(sudo lctl list_nids | head -1)
sudo mount -t lustre -o loop /lustre/mdt.img /mnt/testfs-mdt0 || { echo "MDT mount failed"; dmesg|tail -10; exit 1; }
for i in 0 1 2 3; do sudo mount -t lustre -o loop /lustre/ost$i.img /mnt/testfs-ost$i; done
sleep 4
sudo lctl dl | awk '{print $3, $4}' | head -8

echo
echo "=== does their CLI exist, and what device name does it want? ==="
sudo lctl iterate_objects 2>&1 | head -4
for dev in testfs-MDT0000 testfs-MDT0000-osd; do
	printf '  %-22s -> ' "$dev"
	sudo timeout 60 lctl iterate_objects --count 3 "$dev" 2>&1 | head -2 | tr '\n' ' '
	echo
done
echo "THEIRS UP"
