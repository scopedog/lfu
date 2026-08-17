#!/bin/bash
# Stage 3 (ZFS): MGS + MDT + 2 OSTs + client, all loopback zpools on one node.
#
# llmount.sh with FSTYPE=zfs does this in one step and picks its own dataset
# names; doing it by hand instead keeps the MDT dataset name predictable, which
# the crosscheck stage needs (it exports the pool and reads it with lfind-zfs).
# The client mount still needs an OSS up, hence the OSTs (lfu-gcp-lab).
set -e
cd ~/lustre-release
sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo depmod -a
sudo modprobe zfs
sudo modprobe lustre 2>/dev/null || true

D=/lfu; sudo mkdir -p $D
for f in mdt ost0 ost1; do
	[ -f $D/$f.img ] || sudo truncate -s 24G $D/$f.img
done

echo "=== zpools ==="
sudo zpool list lfu-mdt >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-mdt $D/mdt.img
sudo zpool list lfu-ost0 >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-ost0 $D/ost0.img
sudo zpool list lfu-ost1 >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-ost1 $D/ost1.img

echo "=== mkfs.lustre ==="
sudo mkfs.lustre --mgs --mdt --fsname=lfufs --index=0 --backfstype=zfs \
	--servicenode=$(hostname -i)@tcp lfu-mdt/mdt0 2>&1 | tail -5
for i in 0 1; do
	sudo mkfs.lustre --ost --fsname=lfufs --index=$i --backfstype=zfs \
		--mgsnode=$(hostname -i)@tcp lfu-ost$i/ost$i 2>&1 | tail -3
done

echo "=== dataset properties (xattr=sa is what puts tier 1 in the SA area) ==="
sudo zfs get -H xattr,dnodesize,recordsize,compression lfu-mdt/mdt0

echo "=== mount ==="
sudo mkdir -p /mnt/mdt0 /mnt/ost0 /mnt/ost1 /mnt/lfufs
sudo mount -t lustre lfu-mdt/mdt0 /mnt/mdt0
for i in 0 1; do sudo mount -t lustre lfu-ost$i/ost$i /mnt/ost$i; done
sleep 5
sudo mount -t lustre $(hostname -i)@tcp:/lfufs /mnt/lfufs
df -h /mnt/lfufs | tail -1
sudo lctl get_param -n version | head -1
echo "STAGE3 OK"
