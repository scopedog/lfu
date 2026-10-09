#!/bin/bash
# 10-09 lab, stage 6 (as root): llmount one MDT, 05-once.sh old then fix, cleanup.
set -u
exec > /tmp/lab1009-once-all.out 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1009-llmount.txt 2>&1
mount -t lustre | grep -q "on /mnt/lfst " || { echo "ABORT: no client mount"; exit 4; }
for a in ${ARMS:-old fix}; do bash /tmp/05-once.sh $a; tail -2 /tmp/lab1009-$a-once/run.txt; done
bash ./llmountcleanup.sh > /tmp/lab1009-cleanup.txt 2>&1; echo "cleanup rc=$?"
echo ALL DONE
