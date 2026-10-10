#!/bin/bash
# 10-09 lab, stage 10 (as root): 68415, a failed clear under _FOLLOW.
# Usage: 10-follow.sh <arm>...  Per arm: a fresh user U, the harness reading
# with _FOLLOW|_CLEAR, U deregistered, 1500 creates (> SCAN_CL_CLEAR_BATCH).
#   old: the failed clears are logged and the stream runs on (timeout, 124)
#   new: the stream ends and returns the clear's errno
set -u
exec > /tmp/lab1009-follow.out 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1009-follow-llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
# a second user that stays, so deregistering U does not purge the log
KEEP=$(lctl --device $MDT changelog_register -n -m CREAT)
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; D=$M/follow-$ARM
	gcc -o /tmp/follow_clear-$ARM /tmp/follow_clear.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || { echo "cc $ARM failed"; continue; }
	U=$(lctl --device $MDT changelog_register -n -m CREAT)
	mkdir $D; for i in $(seq 1 10); do touch $D/a$i; done
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) user $U, lib $(ldd /tmp/follow_clear-$ARM | grep -o "$P/lib/liblustreapi.so.1")"
	start=$(date +%s)
	timeout 120 /tmp/follow_clear-$ARM $MDT $U > /tmp/lab1009-follow-$ARM.txt 2>&1 &
	pid=$!
	sleep 5
	lctl --device $MDT changelog_deregister $U && echo "deregistered $U"
	for i in $(seq 1 1500); do touch $D/b$i; done
	wait $pid; wrc=$?
	echo "$ARM: exit $wrc after $(( $(date +%s) - start )) s"
	grep -m3 "RETURNED\|cannot clear" /tmp/lab1009-follow-$ARM.txt
	echo "  'cannot clear' lines: $(grep -c 'cannot clear' /tmp/lab1009-follow-$ARM.txt)"
done
lctl --device $MDT changelog_deregister $KEEP > /dev/null
bash ./llmountcleanup.sh > /tmp/lab1009-follow-cleanup.txt 2>&1; echo "cleanup rc=$?"
echo FOLLOW DONE
