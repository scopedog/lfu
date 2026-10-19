#!/bin/bash
# 10-18 pm lab (root, clone VM): a1018 fix #1 (69443), the in-run recheck of
# an MDT recorded at 0.  Arms: n = c1018-fork-1014 d9cc93e608 (unfixed),
# f = fork-1014 2794517e21 (fixed), g = fork-1014 26f7c0b1f6 (pass d:
# anchor 0 warns, rc 0).  Usage: 06-recheck0.sh <arm> <tag>
#
# Timing is forced, not raced: lfs writes into a FIFO this script reads one
# line from and then stops reading.  With ~190 KB of MDT0000 matches lfs
# blocks in write() while MDT0000 is still being scanned (the script checks
# wchan, the changelog fd lfs holds, and a gdb backtrace).  Only then does
# the other changelog user clear MDT0001, after which the FIFO is drained.
#
# Variant A: the clear is followed by one new record (kept), so MDT0001's
# log moves on.  Variant B (same mount, second pass): the clear empties it.
set -u
ARM=$1; TAG=$2
L=/tmp/lab1018-$ARM/lustre/utils/.libs; OUT=/tmp/lab1018-rc0-$TAG
rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') arm=$ARM ($(cat /tmp/lab1018-$ARM.sha)) tag=$TAG"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; T=/usr/lib64/lustre/tests; cd $T; export PATH=$PATH:$T
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }
echo "lfs ld.so: $(LD_TRACE_LOADED_OBJECTS=1 $L/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "arm lib md5 $(md5sum < $L/liblustreapi.so.1.0.0 | cut -c1-12), 'when the search began' in it: $(grep -c 'when the search began' $L/liblustreapi.so.1.0.0), 'has been purged since' (pass d): $(grep -c 'has been purged since' $L/liblustreapi.so.1.0.0)"

# the directories exist before any changelog user, so their records are not logged
R=$M/r; lfs mkdir -i 0 $R; lfs mkdir -i 0 $R/big; lfs mkdir -i 1 $R/one
lfs mkdir -i 0 $R/big2; lfs mkdir -i 1 $R/one2
echo "dirs: big on MDT$(lfs getdirstripe -m $R/big), one on MDT$(lfs getdirstripe -m $R/one)"
U0=$(lctl --device lfst-MDT0000 changelog_register -n); U1=$(lctl --device lfst-MDT0001 changelog_register -n)
echo "other changelog user: MDT0000 $U0, MDT0001 $U1"
cl() { echo "$(lfs changelog lfst-MDT000$1 | wc -l) recs, first $(lfs changelog lfst-MDT000$1 | head -1 | awk '{print $1, $2}')"; }
clr() { lfs changelog_clear lfst-MDT0000 $U0 0; lfs changelog_clear lfst-MDT0001 $U1 0; }
clr; sync; sleep 2
echo "-- logs before run1: MDT0000 $(cl 0); MDT0001 $(cl 1)"

pass() {	# pass <variant> <big dir> <one dir> <cookie>
	local V=$1 B=$2 O=$3 CK=$4 F=$OUT/fifo.$1 pid w n
	$L/lfs find $R --since-cookie $CK -type f > /dev/null 2> $OUT/run1.$V.err
	echo "-- [$V] run1 rc=$? err=[$(cat $OUT/run1.$V.err)] cookie: $(grep -v '^#' $CK | tr '\n' ';')"
	grep -q '^lfst-MDT0001 0$' $CK || echo "   SHAPE: MDT0001 is not recorded at 0"
	createmany -o $B/a_name_long_enough_to_fill_the_pipe_quickly_ 4000 > /dev/null
	for i in 1 2 3 4 5; do touch $O/lost$i; done
	sync; sleep 3
	echo "   before run2: MDT0000 $(cl 0); MDT0001 $(cl 1)"
	rm -f $F; mkfifo $F
	( $L/lfs find $R --since-cookie $CK -type f > $F 2> $OUT/run2.$V.err
	  echo $? > $OUT/run2.$V.rc ) &
	exec 3< $F
	IFS= read -r first <&3
	for n in $(seq 1 100); do
		pid=$(pgrep -nf "lfs find $R --since-cookie $CK")
		w=$(cat /proc/$pid/wchan 2>/dev/null)
		[ "$w" = pipe_write ] && break
		sleep 0.1
	done
	echo "   lfs pid $pid wchan=$w after ${n} polls; first line: $first"
	echo "   maps: $(grep -o '/[^ ]*liblustreapi[^ ]*' /proc/$pid/maps | sort -u | tr '\n' ' ')"
	echo "   fds: $(ls -l /proc/$pid/fd | grep -o 'changelog[^ ]*\|MDT[^ ]*' | sort -u | tr '\n' ' ')"
	gdb -batch -p $pid -ex 'bt 12' 2>/dev/null | grep -E '^#' | sed 's/^/     /' | cut -c1-160
	lfs changelog_clear lfst-MDT0001 $U1 0
	[ $V = A ] && touch $O/kept
	sync
	echo "   cleared MDT0001$([ $V = A ] && echo ' then touched kept') while lfs is blocked: MDT0001 $(cl 1)"
	cat <&3 > $OUT/run2.$V.out; exec 3<&-
	wait
	{ echo "$first"; cat $OUT/run2.$V.out; } > $OUT/run2.$V.all
	echo "   run2 rc=$(cat $OUT/run2.$V.rc) lines=$(wc -l < $OUT/run2.$V.all) big=$(grep -c "$B/" $OUT/run2.$V.all) lost=$(grep -c '/lost' $OUT/run2.$V.all) kept=$(grep -c '/kept$' $OUT/run2.$V.all)"
	sed 's/^/   stderr: /' $OUT/run2.$V.err
	echo "   cookie after run2: $(grep -v '^#' $CK | tr '\n' ';')"
	$L/lfs find $R --since-cookie $CK -type f > $OUT/run3.$V.out 2> $OUT/run3.$V.err
	echo "   run3 rc=$? lines=$(wc -l < $OUT/run3.$V.out) lost=$(grep -c '/lost' $OUT/run3.$V.out) kept=$(grep -c '/kept$' $OUT/run3.$V.out)"
	sed 's/^/   stderr: /' $OUT/run3.$V.err
	echo "   cookie after run3: $(grep -v '^#' $CK | tr '\n' ';')"
}
pass A $R/big $R/one $OUT/ck.A
clr; sync; sleep 2
echo "-- logs before pass B: MDT0000 $(cl 0); MDT0001 $(cl 1)"
pass B $R/big2 $R/one2 $OUT/ck.B
lctl --device lfst-MDT0000 changelog_deregister $U0; lctl --device lfst-MDT0001 changelog_deregister $U1
cd $T; bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "RECHECK0 DONE"
