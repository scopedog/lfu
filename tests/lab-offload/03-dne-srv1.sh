#!/bin/bash
# DNE server 1: MDT1 only, on its own node so it has its own disk.  $1 = MGS IP
set -e
sudo modprobe lustre; sudo modprobe ldiskfs
mkdir -p ~/img; [ -f ~/img/mdt1.img ] || fallocate -l 16G ~/img/mdt1.img
SZ=$((16 * 1024 * 1024))
sudo mkfs.lustre --fsname=testfs --mdt --index=1 --mgsnode=$1@tcp --device-size=$SZ \
	--mkfsoptions="-I 1024" --reformat ~/img/mdt1.img >/tmp/mkfs.log
sudo mkdir -p /mnt/mdt1
sudo mount -t lustre -o loop ~/img/mdt1.img /mnt/mdt1
mount -t lustre; echo "STAGE3S1 OK"
