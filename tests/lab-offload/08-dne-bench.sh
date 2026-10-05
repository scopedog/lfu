#!/bin/bash
# DNE: walk vs offload with 1 worker vs offload with the default (one per MDT).
# $1 $2 = server IPs.  Caches dropped on all three nodes before cold runs.
S0=$1; S1=$2; N=${N:-5}; M=/mnt/testfs; P="-mtime -30 -type f"
drop() { local h; for h in $S0 $S1; do ssh -o BatchMode=yes $h 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null'; done
	 sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }
echo "== $(lfs --version) $(sudo lfs mdts $M | tr '\n' ' ')"
for t in 1 0; do
	a=(--offload); [ $t = 1 ] && a+=(--threads 1)
	sudo strace -f -e trace=clone,clone3 -o /tmp/st.$t lfs find $M "${a[@]}" $P -uid 4242 >/dev/null
	echo "threads=$t: clones $(grep -c clone /tmp/st.$t)"
done
echo "== oracle: walk vs offload (default workers), sorted"
bad=0
cmp1() { local w=$(sudo lfs find "$@" --no-offload | sort | md5sum) o=$(sudo lfs find "$@" --offload 2>/tmp/e | sort | md5sum) c=$(sudo lfs find "$@" --offload 2>/dev/null | wc -l)
	 [ "$w" = "$o" ] && echo "SAME n=$c  $* $(head -c 120 /tmp/e)" || { echo "DIFF  $*"; diff <(sudo lfs find "$@" --no-offload|sort) <(sudo lfs find "$@" --offload 2>/dev/null|sort) | head -4; bad=1; }; }
cmp1 $M $P; cmp1 $M/bench $P; cmp1 $M/bench/d3 $P; cmp1 $M/bench/d7 $P; cmp1 $M/d0 $P
cmp1 $M/x $P; cmp1 $M/x/y $P; cmp1 $M -type d -mtime -30
[ $bad = 0 ] || { echo ORACLE FAILED; exit 1; }
TIMEFORMAT="%3R"
echo "== timed: scope arm cache wall"
for i in $(seq $N); do
	for s in "" bench/d3; do
		for arm in walk off1 offN; do
			case $arm in walk) a=(--no-offload);; off1) a=(--offload --threads 1);; offN) a=(--offload);; esac
			drop; t=$( { time sudo lfs find $M/$s "${a[@]}" $P >/dev/null; } 2>&1 ); echo "/$s $arm cold $t"
			[ $arm = walk ] && continue
			t=$( { time sudo lfs find $M/$s "${a[@]}" $P >/dev/null; } 2>&1 ); echo "/$s $arm warm $t"
		done
	done
done
echo "STAGE8 OK"
