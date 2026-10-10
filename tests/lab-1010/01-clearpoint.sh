#!/bin/bash
# 10-10 lab, stage 1 (as root on the clone VM): 68415, a clear below the
# user's own clear point (AI PS24).  Usage: 01-clearpoint.sh <arm>...
# Per arm: KEEP lags at 0 and holds the log; U is cleared to the end; the
# harness then reads from record 0 with sc_user=U and _CLEAR.
#   old: the first clear is below U's point, the MDS says -ENOENT, the run
#        returns -2 (and under _FOLLOW ends on it)
#   new: 0; under _FOLLOW it runs on (timeout, 124); U never moves back;
#        later records are still cleared; a deregistered U is still -2
set -u
exec > /tmp/lab1010-clearpoint.out 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1010-llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
users() { lctl get_param -n mdd.$MDT.changelog_users | grep -E "^(current|cl)" | tr -s ' ' | tr '\n' ';'; echo; }
pos() { lctl get_param -n mdd.$MDT.changelog_users | awk -v u=$1 '$1 == u || index($1, u "-") == 1 { print $2 }'; }
KEEP=$(lctl --device $MDT changelog_register -n -m CREAT)
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; D=$M/cp-$ARM
	gcc -o /tmp/clear_point-$ARM /tmp/clear_point.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || { echo "cc $ARM failed"; continue; }
	U=$(lctl --device $MDT changelog_register -n -m CREAT)
	mkdir $D; ./createmany -o $D/a 3000 > /dev/null
	lfs changelog_clear $MDT $U 0; echo "clear-all $U rc=$?"
	before=$(pos $U)
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) user $U at $before, keep $KEEP at $(pos $KEEP); lib $(ldd /tmp/clear_point-$ARM | grep -o "$P/lib/liblustreapi.so.1")"
	/tmp/clear_point-$ARM $MDT $U > /tmp/lab1010-cp-$ARM-1.txt 2>&1
	echo "$ARM plain:  $(grep RETURNED /tmp/lab1010-cp-$ARM-1.txt); 'cannot clear' x$(grep -c 'cannot clear' /tmp/lab1010-cp-$ARM-1.txt); U at $(pos $U)"
	timeout 20 /tmp/clear_point-$ARM $MDT $U follow > /tmp/lab1010-cp-$ARM-2.txt 2>&1
	echo "$ARM follow: exit $? $(grep RETURNED /tmp/lab1010-cp-$ARM-2.txt); U at $(pos $U)"
	# records past U's point are still cleared
	./createmany -o $D/b 1500 > /dev/null
	/tmp/clear_point-$ARM $MDT $U > /tmp/lab1010-cp-$ARM-3.txt 2>&1
	echo "$ARM more:   $(grep RETURNED /tmp/lab1010-cp-$ARM-3.txt); U at $(pos $U) (was $before)"
	# and an unregistered user is still an error
	lctl --device $MDT changelog_deregister $U > /dev/null
	/tmp/clear_point-$ARM $MDT $U > /tmp/lab1010-cp-$ARM-4.txt 2>&1
	echo "$ARM dereg:  $(grep RETURNED /tmp/lab1010-cp-$ARM-4.txt)"
	users
done
lctl --device $MDT changelog_deregister $KEEP > /dev/null
bash ./llmountcleanup.sh > /tmp/lab1010-cleanup.txt 2>&1; echo "cleanup rc=$?"
echo CLEARPOINT DONE
