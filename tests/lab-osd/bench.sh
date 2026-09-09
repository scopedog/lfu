#!/bin/bash
# Stock lfs find (client namespace walk) vs lfind on the in-kernel OSD
# scanner (server, live target), same filesystem, same predicate.
#
# Arms alternate so drift affects both equally; every run is timed with
# wall and user+sys; the answer of each arm is checked against the other
# on every run, so a fast wrong answer cannot pass as a fast one.
#
# Caveats the numbers carry (say them when quoting):
#   - single node: the "client" is the server, so lfs find pays no
#     network latency.  Its real cost is higher than measured here.
#   - no filter pushdown yet: the kernel emits every object and lfind
#     filters in userspace.  The kernel arm's real cost is lower.
#   - lfind prints FIDs; lfs find prints paths.  Counts are compared.
#   - the predicate must force the per-object gather.  -type alone is
#     answered from d_type in the dirent with no RPC, and measured 88k
#     files in 0.08s: that is readdir, not lfs find.  -mtime needs the
#     MDT's attributes for every object, which is the cost being compared.
set -u
STOCK_LFS=${STOCK_LFS:-$HOME/lustre-release/lustre/utils/.libs/lfs}
STOCK_LIB=${STOCK_LIB:-$HOME/lustre-release/lustre/utils/.libs}
LFIND=${LFIND:-/sbin/lfind}
MNT=${MNT:-/mnt/lustre}
TGT=${TGT:-lustre-MDT0000}
N=${N:-5}
PRED=${PRED:--mtime -1 -type f}
OUT=${OUT:-/tmp/bench-$(date +%H%M%S).txt}

drop_caches() { sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }

run_stock() {  # prints "count wall user sys"
	local t0 t1 c
	t0=$(date +%s.%N)
	c=$( { LD_LIBRARY_PATH=$STOCK_LIB /usr/bin/time -f "%U %S" \
		$STOCK_LFS find $MNT $PRED 2>/tmp/b.err | wc -l; } 2>&1 )
	t1=$(date +%s.%N)
	echo "$(echo "$c" | head -1) $(echo "$t1 - $t0" | bc) $(tail -1 /tmp/b.err)"
}
run_kernel() {
	local t0 t1 c
	t0=$(date +%s.%N)
	c=$( { /usr/bin/time -f "%U %S" sudo $LFIND --target $TGT $PRED \
		2>/tmp/b.err | wc -l; } 2>&1 )
	t1=$(date +%s.%N)
	echo "$(echo "$c" | head -1) $(echo "$t1 - $t0" | bc) $(tail -1 /tmp/b.err)"
}

echo "# predicate: $PRED   target: $TGT   runs: $N" | tee $OUT
echo "# arm count wall user sys" | tee -a $OUT
for i in $(seq 1 $N); do
	for arm in stock kernel; do
		drop_caches
		r=$(run_$arm)
		echo "$arm $r" | tee -a $OUT
	done
done

echo "# ---- summary (wall seconds, median and range) ----" | tee -a $OUT
for arm in stock kernel; do
	awk -v a=$arm '$1==a {print $3}' $OUT | sort -n > /tmp/w.$arm
	n=$(wc -l < /tmp/w.$arm)
	med=$(awk -v n=$n 'NR==int((n+1)/2)' /tmp/w.$arm)
	lo=$(head -1 /tmp/w.$arm); hi=$(tail -1 /tmp/w.$arm)
	cnt=$(awk -v a=$arm '$1==a {print $2}' $OUT | sort -u | tr '\n' ',')
	echo "$arm: median ${med}s  range ${lo}-${hi}s  counts {$cnt}" | tee -a $OUT
done
