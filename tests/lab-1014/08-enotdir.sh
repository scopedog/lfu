#!/bin/bash
# 10-14 lab (root, clone VM): lreview finding 4 on 68416'.  A directory above
# the object is renamed and a FILE made at its old name, between fid2path
# and the gather: the statx() or the parent's openat() fails with ENOTDIR.
#   old (f1): some calls answer -ENOTDIR (counted "other") for a live file
#   new (g1): -ENOTDIR is retried, so they answer 0
#  E1: mv a b; touch a; rm a; mv b a, without pause
#  E2: the same with 20 ms pauses
#  R1: the plain rename race of lab-1013/06, to show nothing regressed
set -u
O=/tmp/lab1014-enotdir; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
	gcc -O2 -o /tmp/scanfid_race-$ARM /tmp/scanfid_race.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || { echo "cc $ARM failed"; continue; }
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) lib $(ldd /tmp/scanfid_race-$ARM | grep -o "$P/lib/liblustreapi.so.1")"
	D=$M/en-$ARM; mkdir -p $D/a/sub; echo x > $D/a/sub/f
	FID=$(lfs path2fid $D/a/sub/f)
	( while :; do mv $D/a $D/b; touch $D/a; rm -f $D/a; mv $D/b $D/a; done ) 2>/dev/null &
	ren=$!; sleep 1
	/tmp/scanfid_race-$ARM $M "$FID" 20000 > $O/$ARM-E1.txt 2>&1
	kill $ren; wait $ren 2>/dev/null
	[ -f $D/a ] && rm -f $D/a; [ -d $D/b ] && mv $D/b $D/a
	echo "E1 $ARM file at the old name, no pause: $(cat $O/$ARM-E1.txt)"
	( while :; do mv $D/a $D/b; touch $D/a; sleep 0.02; rm -f $D/a; mv $D/b $D/a; sleep 0.02; done ) 2>/dev/null &
	ren=$!; sleep 1
	/tmp/scanfid_race-$ARM $M "$FID" 20000 > $O/$ARM-E2.txt 2>&1
	kill $ren; wait $ren 2>/dev/null
	[ -f $D/a ] && rm -f $D/a; [ -d $D/b ] && mv $D/b $D/a
	echo "E2 $ARM file at the old name, 20 ms:    $(cat $O/$ARM-E2.txt)"
	( while :; do mv $D/a $D/b; mv $D/b $D/a; done ) 2>/dev/null &
	ren=$!; sleep 1
	/tmp/scanfid_race-$ARM $M "$FID" 20000 > $O/$ARM-R1.txt 2>&1
	kill $ren; wait $ren 2>/dev/null
	[ -d $D/b ] && mv $D/b $D/a
	echo "R1 $ARM plain rename flip-flop:        $(cat $O/$ARM-R1.txt)"
done
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo ENOTDIR DONE
