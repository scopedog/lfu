#!/bin/bash
# Stage 3: MGS+MDT and two OSTs as ZFS pools on real block devices, plus a
# client, all on one node.
#
# Real devices, not the loop files the other ZFS lab used: an exported pool is
# found by reading vdev labels under /dev, which is where a deployed target
# lives and where the backend looks.  A file-backed pool would need a search
# path the API does not have.
set -e
cd ~/lustre-release
sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo depmod -a
sudo modprobe zfs
sudo modprobe lustre 2>/dev/null || true

MDTDEV=/dev/nvme0n2
OSTDEV0=/dev/nvme0n3
OSTDEV1=/dev/nvme0n4
IP=$(hostname -i)

echo "=== zpools on real devices ==="
sudo zpool list lfu-mdt  >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-mdt  $MDTDEV
sudo zpool list lfu-ost0 >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-ost0 $OSTDEV0
sudo zpool list lfu-ost1 >/dev/null 2>&1 || sudo zpool create -f -o cachefile=none lfu-ost1 $OSTDEV1
sudo zpool list

echo "=== mkfs.lustre ==="
# No --servicenode: it marks the target as having a failover partner and
# mkfs.lustre then refuses on ZFS with "spl_hostid not set".
if ! sudo zfs list lfu-mdt/mdt0 >/dev/null 2>&1; then
	sudo mkfs.lustre --mgs --mdt --fsname=lfufs --index=0 \
		--backfstype=zfs lfu-mdt/mdt0 > /tmp/mkfs-mdt.log 2>&1 || {
		echo "MDT mkfs FAILED:"; tail -20 /tmp/mkfs-mdt.log; exit 1; }
	echo "  MDT created"
fi
for i in 0 1; do
	if ! sudo zfs list lfu-ost$i/ost$i >/dev/null 2>&1; then
		sudo mkfs.lustre --ost --fsname=lfufs --index=$i --backfstype=zfs \
			--mgsnode=$IP@tcp lfu-ost$i/ost$i > /tmp/mkfs-ost$i.log 2>&1 || {
			echo "OST$i mkfs FAILED:"; tail -20 /tmp/mkfs-ost$i.log; exit 1; }
		echo "  OST$i created"
	fi
done

echo "=== the svname property the backend reads its label from ==="
sudo zfs get -H -o property,value lustre:svname lfu-mdt/mdt0
sudo zfs get -H -o property,value lustre:svname lfu-ost0/ost0
sudo zfs get -H xattr,dnodesize lfu-mdt/mdt0

echo "=== mount ==="
sudo mkdir -p /mnt/mdt0 /mnt/ost0 /mnt/ost1 /mnt/lfufs
mountpoint -q /mnt/mdt0 || sudo mount -t lustre lfu-mdt/mdt0 /mnt/mdt0
for i in 0 1; do mountpoint -q /mnt/ost$i || sudo mount -t lustre lfu-ost$i/ost$i /mnt/ost$i; done
sleep 5
mountpoint -q /mnt/lfufs || sudo mount -t lustre $IP@tcp:/lfufs /mnt/lfufs
df -h /mnt/lfufs | tail -1
echo "STAGE3 OK"
