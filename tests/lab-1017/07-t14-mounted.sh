#!/bin/bash
# 10-17 lab (root, clone VM): 05-t14.sh on a mounted Lustre -- test14 refuses
# a local directory ("not a Lustre filesystem").
set -u
N=${1:-40}; OUT=/tmp/lab1017-t14.txt; : > $OUT
mount | grep -q ' type lustre' && { echo "ABORT: mounted" >> $OUT; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1017-t14-llmount.txt 2>&1
M=/mnt/lfst
for i in $(seq 1 24); do taskset -c 0 sh -c 'while :; do :; done' & done
for a in o2 n2 o2 n2; do
	W=$M/t14-$a; rm -rf $W; mkdir -p $W
	pass=0 fail=0 won=0 missed=0
	for i in $(seq 1 $N); do
		LD_PRELOAD=/tmp/lab1009-$a/lustre/utils/.libs/liblustreapi.so.1 \
		taskset -c 0 /tmp/lab1009-$a/lustre/tests/.libs/llapi_scan_test \
			-d $W -t 14 > /tmp/t14-$a.out 2>&1 && pass=$((pass+1)) || {
			fail=$((fail+1)); grep -m1 -i "assert\|fail\|error" /tmp/t14-$a.out >> $OUT; }
		grep -q "won the race" /tmp/t14-$a.out && won=$((won+1))
		grep -q "missed the window" /tmp/t14-$a.out && missed=$((missed+1))
		rm -rf $W/*
	done
	echo "$a ($(cat /tmp/lab1009-$a.sha)): pass=$pass fail=$fail won=$won missed=$missed of $N" >> $OUT
done
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null
bash ./llmountcleanup.sh > /tmp/lab1017-t14-cleanup.txt 2>&1
echo "T14 DONE" >> $OUT
