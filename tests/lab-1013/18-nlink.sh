#!/bin/bash
# 10-13 lab: does the master inode's link count differ from the striped
# directory's?  20 subdirectories hash over both stripes.  Usage: 18-nlink.sh <old> <new>
set -u
O=/tmp/lab1013-18; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst OSTCOUNT=1 MDSCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; IMG=/tmp/lfst-mdt1
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
lfs mkdir -i 0 -c 2 $M/sd; sleep 2
for i in $(seq 1 20); do mkdir $M/sd/d$i; done
echo "walk: sd $(stat -c '%h links, ctime %Z, mtime %Y, inode %i' $M/sd)"
echo "subdirs per stripe: $(for i in $(seq 1 20); do lfs getstripe -m $M/sd/d$i; done | sort | uniq -c | tr '\n' ' ')"
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1
echo "master inode on MDT0: $(debugfs -R 'stat /ROOT/sd' $IMG 2>/dev/null | grep -o 'Links: [0-9]*')"
for ARM in "$@"; do
	P=/tmp/arm1009$ARM; LFS=/tmp/lab1009-$ARM/lustre/utils/.libs/lfs
	echo "== $ARM: $(LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device $IMG -type d --mdt-count 2 -printf 'n=%n t=%T@ c=%C@ w=%W@' 2>&1)"
done
echo DONE18
