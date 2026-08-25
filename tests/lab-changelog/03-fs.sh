#!/bin/bash
# Stage 3: one node carrying MGS+MDT+OST on loop files, plus a client mount.
# The client mount needs an OSS up, so an OST is formatted even though this
# test only reads the namespace.
set -e
sudo modprobe lustre || true
sudo modprobe ldiskfs || true

mkdir -p ~/img
for f in mdt ost0; do
	[ -f ~/img/$f.img ] || fallocate -l 8G ~/img/$f.img
done

# mkfs.lustre on a loop FILE needs --device-size in KB and will not infer it.
SZ=$((8 * 1024 * 1024))
sudo mkfs.lustre --fsname=testfs --mgs --mdt --index=0 \
	--device-size=$SZ --mkfsoptions="-I 1024" --reformat ~/img/mdt.img
sudo mkfs.lustre --fsname=testfs --ost --index=0 --mgsnode=$(hostname -i)@tcp \
	--device-size=$SZ --reformat ~/img/ost0.img

sudo mkdir -p /mnt/mdt0 /mnt/ost0 /mnt/testfs
sudo mount -t lustre -o loop ~/img/mdt.img /mnt/mdt0
sudo mount -t lustre -o loop ~/img/ost0.img /mnt/ost0
sudo mount -t lustre $(hostname -i)@tcp:/testfs /mnt/testfs
sudo chmod 777 /mnt/testfs
df -t lustre -h
echo "STAGE3 OK"
