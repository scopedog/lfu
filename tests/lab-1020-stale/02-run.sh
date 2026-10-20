#!/bin/bash
# 10-20 stale-inode lab, stage 2 (as root on the clone VM), after 01-build.sh
# -full new old.  Each arm runs from its own build tree; nothing installed.
#   Q: quiescent fixture, delay 0: the ring (ringdump) and the RPC path
#      (mountdump) must give the same records on both arms.
#   C: create/unlink churn with lab_delay_us widening next() -> xattrs.
#      old should emit mixed records; new should emit none and count stale.
# Order: old Q, new Q, new C, old C -- both Q runs see the fixture untouched.
set -u
OUT=/tmp/stale-lab; FX=/tmp/stalefs
DELAY=${DELAY:-2000}; K=${K:-200}; ROUNDS=${ROUNDS:-5}
rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') delay=${DELAY}us K=$K"
lsmod | grep -q -E '^(lnet|obdclass) ' && { echo "ABORT: Lustre modules loaded"; exit 2; }

up() {	# arm noformat
	local n=$1 T=/tmp/stale-$1
	export LUSTRE=$T/lustre FSTYPE=ldiskfs MDSCOUNT=1 OSTCOUNT=1 TMP=$FX \
		MDSSIZE=400000 OSTSIZE=800000
	mkdir -p $FX
	# any non-empty NOFORMAT, "0" too, skips the format
	if [ $2 = 1 ]; then
		(cd $T/lustre/tests && NOFORMAT=1 bash llmount.sh)
	else
		(cd $T/lustre/tests && bash llmount.sh)
	fi > $OUT/llmount.$n.$2.txt 2>&1
	mount -t lustre | grep -q MDT0000 || { echo "ABORT: $n did not mount"; tail -20 $OUT/llmount.$n.$2.txt; exit 4; }
	insmod $T/lustre/lfu/lfu.ko || { echo "ABORT: lfu.ko"; exit 4; }
	for m in obdclass osd_ldiskfs lfu; do
		local k=$(find $T/lustre -name $m.ko | head -1)
		[ "$(cat /sys/module/$m/srcversion)" = "$(modinfo -F srcversion $k)" ] ||
			{ echo "ABORT: loaded $m is not $n's"; exit 4; }
	done
	echo "-- $n up (noformat=$2), modules verified from $T"
}
down() {
	local T=/tmp/stale-$1
	echo 0 > /sys/module/lfu/parameters/lab_delay_us
	rmmod lfu
	(cd $T/lustre/tests && bash llmountcleanup.sh) > $OUT/cleanup.$1.txt 2>&1
	lsmod | grep -q -E '^(lnet|obdclass) ' && { echo "ABORT: modules still loaded"; exit 4; }
	echo "-- $1 down"
}
quiet() {
	local T=/tmp/stale-$1
	$T/ringdump lustre-MDT0000 2> $OUT/q.$1.stats | sort > $OUT/q.$1.txt
	$T/mountdump /mnt/lustre 2> $OUT/m.$1.err | sort > $OUT/m.$1.txt
	echo "Q $1: ring $(wc -l < $OUT/q.$1.txt) records, $(cat $OUT/q.$1.stats); mount $(wc -l < $OUT/m.$1.txt) records, $(cat $OUT/m.$1.err)"
}
churn() {
	local n=$1 T=/tmp/stale-$1 d=/mnt/lustre/churn.$1 r
	mkdir $d; local dfid=$($T/utils/lfs path2fid $d 2>/dev/null || $T/lustre/utils/lfs path2fid $d)
	rm -f $OUT/stop; python3 /tmp/churn.py $d $K $OUT/stop > $OUT/churn.$n.out 2>&1 &
	# the MDT keeps an unlinked inode until its object leaves the cache,
	# so without purging a freed inode number is not reused for seconds
	( while [ ! -e $OUT/stop ]; do echo 2 > /proc/sys/vm/drop_caches; sleep 0.2; done ) &
	sleep 3
	echo $DELAY > /sys/module/lfu/parameters/lab_delay_us
	for r in $(seq 1 $ROUNDS); do
		$T/ringdump lustre-MDT0000 > $OUT/c.$n.$r.txt 2> $OUT/c.$n.$r.stats
		echo "C $n round $r: $(python3 /tmp/check.py $OUT/c.$n.$r.txt $dfid | head -4 | tr '\n' ' ') | $(cat $OUT/c.$n.$r.stats)"
	done
	echo 0 > /sys/module/lfu/parameters/lab_delay_us
	touch $OUT/stop; wait; echo "C $n: $(cat $OUT/churn.$n.out)"
}

up old 0
mkdir /mnt/lustre/static
for d in $(seq 0 9); do mkdir /mnt/lustre/static/d$d
	(cd /mnt/lustre/static/d$d && seq 0 499 | sed 's/^/f/' | xargs touch); done
sync; sleep 10
quiet old
down old
up new 1
quiet new
echo "Q ring old vs new: $(diff $OUT/q.old.txt $OUT/q.new.txt | grep -c '^[<>]') lines differ"
echo "Q mount old vs new: $(diff $OUT/m.old.txt $OUT/m.new.txt | grep -c '^[<>]') lines differ"
churn new
down new
up old 1
churn old
down old
echo "== end $(date '+%F %T')"
