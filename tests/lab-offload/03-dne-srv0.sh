#!/bin/bash
# DNE server 0: MGS + MDT0 + OST0 on loop files.
set -e
sudo modprobe lustre; sudo modprobe ldiskfs
mkdir -p ~/img
for f in mdt ost0; do [ -f ~/img/$f.img ] || fallocate -l 16G ~/img/$f.img; done
SZ=$((16 * 1024 * 1024)); NID=$(hostname -i)@tcp
sudo mkfs.lustre --fsname=testfs --mgs --mdt --index=0 --device-size=$SZ \
	--mkfsoptions="-I 1024" --reformat ~/img/mdt.img >/tmp/mkfs.log
sudo mkfs.lustre --fsname=testfs --ost --index=0 --mgsnode=$NID \
	--device-size=$SZ --reformat ~/img/ost0.img >>/tmp/mkfs.log
sudo mkdir -p /mnt/mdt0 /mnt/ost0
sudo mount -t lustre -o loop ~/img/mdt.img /mnt/mdt0
sudo mount -t lustre -o loop ~/img/ost0.img /mnt/ost0
mount -t lustre; echo "STAGE3S0 OK"
