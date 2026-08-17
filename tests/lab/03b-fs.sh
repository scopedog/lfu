#!/bin/bash
# Stage 3b: format and mount.  mkfs.lustre on a loop-backed file needs an
# explicit --device-size (KB); it will not infer it.
set -e
NID=$(sudo lctl list_nids | head -1)
echo "NID=$NID"
SZ=$((20 * 1024 * 1024))    # 20 GiB in KB

sudo mkfs.lustre --fsname=testfs --mgs --mdt --index=0 --reformat \
	--device-size=$SZ --mkfsoptions="-I 1024" /lustre/mdt.img \
	> /tmp/mkfs-mdt.log 2>&1 || { tail -25 /tmp/mkfs-mdt.log; exit 1; }
sudo mkfs.lustre --fsname=testfs --ost --index=0 --reformat \
	--device-size=$SZ --mgsnode="$NID" /lustre/ost0.img \
	> /tmp/mkfs-ost.log 2>&1 || { tail -25 /tmp/mkfs-ost.log; exit 1; }
echo "--- MDT inode size (1024 is what puts LMA/LOV/SOM inline) ---"
sudo dumpe2fs -h /lustre/mdt.img 2>/dev/null | grep -iE 'inode size|inode count|features' | head -3

sudo mkdir -p /mnt/testfs-mdt0 /mnt/testfs-ost0 /mnt/testfs
sudo mount -t lustre -o loop /lustre/mdt.img  /mnt/testfs-mdt0
sudo mount -t lustre -o loop /lustre/ost0.img /mnt/testfs-ost0
sudo mount -t lustre "$NID":/testfs /mnt/testfs
sudo lctl dl
df -h /mnt/testfs | tail -1
echo "=== OSD device name for lfu_ring ==="
sudo lctl dl | awk '$3=="osd-ldiskfs"{print $4}'
echo "STAGE3 OK"
