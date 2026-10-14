#!/bin/bash
# 10-14 lab (root, clone VM): lreview finding 1 on 68726.  llapi_scan_test
# test18 from the fixed arm n1014c, run against the unfixed library
# (n1014b) and the fixed one (n1014c), three times each.
set -u
O=/tmp/lab1014-t18; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests; export PATH=/usr/lib64/lustre/tests:$PATH
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
TB=/tmp/lab1009-n1014c/lustre/tests/.libs/llapi_scan_test
for arm in n1014b n1014c; do
	for i in 1 2 3; do
		mkdir -p $M/t18
		LD_PRELOAD=/tmp/arm1009$arm/lib/liblustreapi.so.1 $TB -d $M/t18 -t 18 > $O/$arm-$i.txt 2>&1
		echo "$arm run $i: rc=$? $(grep -m1 -E 'filter ran|PASS|FAIL' $O/$arm-$i.txt)"
		rm -rf $M/t18
	done
done
echo "--- all of llapi_scan_test on n1014c"
mkdir -p $M/all; LD_PRELOAD=/tmp/arm1009n1014c/lib/liblustreapi.so.1 $TB -d $M/all -p /tmp > $O/all.txt 2>&1
echo "rc=$?"; grep -cE "^PASS|: PASS|passed" $O/all.txt; tail -3 $O/all.txt
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "T18 RUN DONE"
