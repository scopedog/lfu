#!/bin/bash
# 10-15 lab (root, clone VM): lreview finding 1/2 on the rate change.  test19
# from arm r3 (the test that makes the race), against the library before the fix (r1) and after
# (r2): a paced scan stopped at its first record must not deliver again.
set -u
O=/tmp/lab1014-ratestop; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
TB=/tmp/lab1009-r3/lustre/tests/.libs/llapi_scan_test
for arm in r1 r2; do
	for i in 1 2 3; do
		mkdir -p $M/t19
		LD_PRELOAD=/tmp/arm1009$arm/lib/liblustreapi.so.1 $TB -d $M/t19 -t 19 > $O/$arm-$i.txt 2>&1
		echo "$arm run $i: rc=$? $(grep -m1 -E 'assertion|pass$' $O/$arm-$i.txt | cut -c1-160)"
		rm -rf $M/t19
	done
done
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "RATESTOP DONE"
