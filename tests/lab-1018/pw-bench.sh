#!/bin/bash
# 10-18 pfind-wait lab (root, clone VM): A/B the busy wait in
# pfind_param_callback(). Arms: m = stock master-1014, pw = the fix.
# One lfs binary (m's), the arm picked by LD_PRELOAD, proven by maps.
set -u
# PRED: the find predicate; EXTRA=0 skips the shutdown and hang parts
PRED=${PRED:--type f}; EXTRA=${EXTRA:-1}; NR=${NR:-6}
OUT=/tmp/lab1018-pw-bench${TAG:-}; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') PRED=[$PRED] EXTRA=$EXTRA NR=$NR"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 MDSSIZE=800000 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; D=$M/pw
LFS=/tmp/lab1018-m/lustre/utils/.libs/lfs
lib() { echo /tmp/lab1018-$1/lustre/utils/.libs/liblustreapi.so.1; }
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }

# fixture: 100 dirs x 1000 files (mknod, MDT only), built once
mkdir $D
for i in $(seq 0 99); do
	mkdir $D/d$i && /usr/lib64/lustre/tests/createmany -m $D/d$i/f 1000 > /dev/null
done
echo "fixture: $(find $D -type f | wc -l) files, $(find $D -type d | wc -l) dirs"
for a in m pw; do echo "arm $a lib md5 $(md5sum < $(lib $a) | cut -c1-12)"; done

# run <arm> <tag> <args...>: wall, process user/sys, main-thread user/sys
run() {
	local a=$1 t=$2; shift 2
	local o=$OUT/$t.out s0 s1 last="" p rc
	s0=$(date +%s.%N)
	LD_PRELOAD=$(lib $a) timeout 120 $LFS "$@" > $o 2> $o.err &
	p=$!
	sleep 0.05
	# timeout's child is lfs
	local c=$(pgrep -P $p -x lfs)
	[ -n "$c" ] && grep -o '/[^ ]*liblustreapi[^ ]*' /proc/$c/maps | sort -u > $OUT/$t.maps
	while [ -n "$c" ] && [ -r /proc/$c/task/$c/stat ]; do
		last=$(awk '{print $14, $15}' /proc/$c/task/$c/stat 2>/dev/null) || break
		sleep 0.02
	done
	wait $p; rc=$?
	s1=$(date +%s.%N)
	echo "$a $t rc=$rc wall=$(awk "BEGIN{printf \"%.3f\", $s1 - $s0}") main_ticks(u s)=[$last] lines=$(wc -l < $o) md5=$(sort $o | md5sum | cut -c1-8) lib=$(cat $OUT/$t.maps 2>/dev/null | tr '\n' ' ')"
}

# CPU via /usr/bin/time too (process total, includes workers)
tm() {
	local a=$1 t=$2; shift 2
	LD_PRELOAD=$(lib $a) /usr/bin/time -f "$a $t TIME wall=%e user=%U sys=%S" \
		timeout 120 $LFS "$@" > $OUT/$t.tout 2>> $OUT/time.txt
	tail -1 $OUT/time.txt
}

clr() { lctl set_param -n ldlm.namespaces.*mdc*.lru_size=clear > /dev/null; }

echo "== warm-up"
run m w0 find $D --threads 4 $PRED; run pw w1 find $D --threads 4 $PRED

for mode in cold warm; do
	echo "== $mode (cold = mdc lock LRU cleared before each run)"
	for r in $(seq 1 $NR); do
		for a in m pw; do
			[ $mode = cold ] && clr
			run $a $mode-$a-$r find $D --threads 4 $PRED
			[ $mode = cold ] && clr
			tm $a $mode-$a-$r find $D --threads 4 $PRED
		done
	done
done

if [ $EXTRA = 1 ]; then
echo "== shutdown path (LLAPI_FAIL_PFIND_SEM)"
export LLAPI_FAIL_LOC=LLAPI_FAIL_PFIND_SEM
for r in $(seq 1 10); do
	for a in m pw; do
		run $a fail-$a-$r find $D --threads 4 -type f
		echo "   err: $(head -c 200 $OUT/fail-$a-$r.out.err | tr '\n' ' ')"
	done
done
unset LLAPI_FAIL_LOC

echo "== hang probe: 200 small finds per thread count on the fix"
for th in 2 4 8 16; do
	n=0; bad=0
	for r in $(seq 1 50); do
		LD_PRELOAD=$(lib pw) timeout 30 $LFS find $D/d$((r % 100)) --threads $th > /dev/null
		rc=$?; n=$((n + 1)); [ $rc != 0 ] && bad=$((bad + 1))
	done
	echo "threads=$th runs=$n nonzero=$bad"
done
LD_PRELOAD=$(lib pw) timeout 60 $LFS find $D --threads 1 -type f | wc -l | sed 's/^/threads=1 lines=/'
fi

bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo "BENCH DONE"
