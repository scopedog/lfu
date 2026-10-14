#!/bin/bash
# 10-13 lab (as root on the clone VM): 68416, a rename between fid2path and
# the gather.  A harness calls llapi_scan_fid() on one live file 20000 times
# while a loop renames the directory above it.  Usage: 06-rename.sh <arm>...
#   old: some calls answer -ENOENT or -ESTALE for a file that always exists
#   new: the lookup is repeated, so they answer 0
#  R1: the directory flips between two names without pause
#  R2: one rename every 20 ms
#  R3: no renames (control), and a FID that is really gone still says so
set -u
O=/tmp/lab1013-rn; rm -rf $O; mkdir -p $O
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
	D=$M/rn-$ARM; mkdir -p $D/a/sub; echo x > $D/a/sub/f
	# before any rename: a path lookup would race with them
	FID=$(lfs path2fid $D/a/sub/f)
	( while :; do mv $D/a $D/b; mv $D/b $D/a; done ) 2>/dev/null &
	ren=$!
	sleep 1
	/tmp/scanfid_race-$ARM $M "$FID" 20000 > $O/$ARM-R1.txt 2>&1
	kill $ren; wait $ren 2>/dev/null
	[ -d $D/b ] && mv $D/b $D/a
	echo "R1 $ARM flip-flop:  $(cat $O/$ARM-R1.txt)"
	( while :; do mv $D/a $D/b; sleep 0.02; mv $D/b $D/a; sleep 0.02; done ) 2>/dev/null &
	ren=$!
	sleep 1
	/tmp/scanfid_race-$ARM $M "$FID" 20000 > $O/$ARM-R2.txt 2>&1
	kill $ren; wait $ren 2>/dev/null
	[ -d $D/b ] && mv $D/b $D/a
	echo "R2 $ARM every 20 ms: $(cat $O/$ARM-R2.txt)"
	echo "R3 $ARM no renames:  $(/tmp/scanfid_race-$ARM $M $D/a/sub/f 20000 2>&1)"
	echo y > $D/a/gone
	echo "R3 $ARM unlinked:    $(/tmp/scanfid_race-$ARM $M $D/a/gone 100 unlink 2>&1)"
done
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo RENAME DONE
