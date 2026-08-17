#!/bin/bash
# Stage 13: is the flat ~190k obj/s cold rate the scanner, or the disk?
# 302,122 objects x 1 KiB inodes = ~302 MB of inode table, so 190k obj/s is
# ~190 MB/s.  If the raw device gives about that, the cold rows are simply
# device-bound and say nothing about readahead.
set -e
sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
echo "=== disk ==="
lsblk -d -o NAME,SIZE,ROTA,MODEL 2>/dev/null | head -5
echo
echo "=== raw sequential read, one reader, 2 GiB off the MDT loop file ==="
sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
sudo dd if=/lustre/mdt.img of=/dev/null bs=1M count=2048 iflag=direct 2>&1 | tail -1
echo
echo "=== raw sequential read of the backing block device ==="
sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
sudo dd if=/dev/nvme0n1 of=/dev/null bs=1M count=2048 iflag=direct 2>&1 | tail -1
echo
echo "=== 4 KiB random read depth 1 (the latency the iget path would see) ==="
sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
sudo dd if=/lustre/mdt.img of=/dev/null bs=4k count=8192 iflag=direct 2>&1 | tail -1
echo
echo "=== how much of the inode table is actually in use ==="
sudo dumpe2fs -h /lustre/mdt.img 2>/dev/null | grep -iE 'Inode count|Free inodes|Inode size|Block count'
