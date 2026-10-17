#!/bin/bash
# 10-17 lab (nishida, clone VM): 68726 9954f2b7.  llapi_scan_test test14 on a
# local directory, every thread pinned to CPU 0 beside busy loops, so the main
# thread can be descheduled past the helper's 50 ms.  Old (o2) vs new (n2).
set -u
N=${1:-40}; OUT=/tmp/lab1017-t14.txt; : > $OUT
for i in $(seq 1 24); do taskset -c 0 sh -c 'while :; do :; done' & done
for a in o2 n2 o2 n2; do
	W=/tmp/t14-$a; rm -rf $W; mkdir -p $W
	pass=0 fail=0 won=0 missed=0
	for i in $(seq 1 $N); do
		LD_PRELOAD=/tmp/lab1009-$a/lustre/utils/.libs/liblustreapi.so.1 \
		taskset -c 0 /tmp/lab1009-$a/lustre/tests/.libs/llapi_scan_test \
			-d $W -t 14 > $W.out 2>&1 && pass=$((pass+1)) || {
			fail=$((fail+1)); grep -m1 -i "assert\|fail" $W.out >> $OUT; }
		grep -q "won the race" $W.out && won=$((won+1))
		grep -q "missed the window" $W.out && missed=$((missed+1))
		rm -rf $W/*
	done
	echo "$a ($(cat /tmp/lab1009-$a.sha)): pass=$pass fail=$fail won=$won missed=$missed of $N" >> $OUT
done
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null
echo "T14 DONE" >> $OUT
