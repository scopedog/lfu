#!/bin/bash
# 10-17 lab (root, clone VM): lreview on 68288 claims llapi_root_path_open()
# of the client mount hangs while MDT0000 is stopped (an MDS open).  Stop
# mds1, time open() of the mount root, then the real lfs call path.
set -u
OUT=/tmp/lab1017-rootopen.txt; : > $OUT
mount | grep -q ' type lustre' && { echo "ABORT: mounted" >> $OUT; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1017-ro-llmount.txt 2>&1
M=/mnt/lfst
mkdir -p $M/d; touch $M/d/f; sync
umount /mnt/lustre-mds1 2>/dev/null || umount $(mount -t lustre | awk '/mdt|mds1/{print $3; exit}')
echo "MDT0000 mounted after stop: $(mount -t lustre | grep -c -i 'mdt\|mds')" >> $OUT
s=$(date +%s.%N)
timeout 30 python3 -c "import os; fd=os.open('$M', os.O_RDONLY|os.O_DIRECTORY|os.O_NONBLOCK); print('open ok fd', fd)" >> $OUT 2>&1
echo "open of the mount root: rc=$? in $(echo "$(date +%s.%N) - $s" | bc) s" >> $OUT
s=$(date +%s.%N)
timeout 60 /tmp/lab1009-n1/lustre/utils/.libs/lfs path2fid $M >> $OUT 2>&1
echo "lfs path2fid root: rc=$? in $(echo "$(date +%s.%N) - $s" | bc) s" >> $OUT
umount -f $M >/dev/null 2>&1
bash ./llmountcleanup.sh > /tmp/lab1017-ro-cleanup.txt 2>&1
echo "ROOTOPEN DONE" >> $OUT
