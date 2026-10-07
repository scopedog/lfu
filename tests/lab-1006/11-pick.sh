#!/bin/bash
# 10-06 lab, stage 11b (as root on the clone VM): #2, "find --since, pick
# before the gather".  OLD = pold bc5e232bd9, NEW = pnew 0a175c4191.
# ldiskfs DNE fixture (FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2), one registered
# user on each MDT.
#
# P1: the answer is byte-identical, stdout and stderr, over a small subtree
#     with a hardlink whose first link is outside it, a rename in and a
#     rename out, inside a big changed tree; rooted at small and at $M.
# P2: the cost of `lfs find $M/small --since 1h`, arms alternated, 5 runs
#     each, wall time and MDC RPC deltas; and the whole fs, 3 each.
set -u
OUT=/tmp/lab1006-pick; M=/mnt/lfst; M0=lfst-MDT0000; M1=lfst-MDT0001
NBIG=${NBIG:-20000}
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 /tmp/lab1006-$n/lustre/utils/.libs/lfs "$@"; }
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for n in pold pnew; do
	l=$(LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1006-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')
	echo "$n ($(cat /tmp/lab1006-$n.sha)) lfs loads:$l  pre_cb=$(nm /tmp/lab1006-$n/lustre/utils/.libs/liblustreapi.so.1 2>/dev/null | grep -c find_since_pre_cb)"
	echo "$l" | grep -q "/tmp/arm1006$n/lib/liblustreapi.so.1" || { echo "ABORT: $n loads the wrong liblustreapi"; exit 3; }
done
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
u0=$(lctl --device $M0 changelog_register -n)
u1=$(lctl --device $M1 changelog_register -n)
echo "users: $u0 $u1"

# ---- the tree, all inside the window -------------------------------------
lfs mkdir -i 0 $M/small && lfs mkdir -i 0 $M/big || { echo "ABORT: mkdir"; exit 5; }
lfs mkdir -i 0 $M/big/d0 && lfs mkdir -i 1 $M/big/d1 &&
	lfs mkdir -i 0 $M/big/d2 && lfs mkdir -i 1 $M/big/d3 || { echo "ABORT: mkdir big"; exit 5; }
t0=$(date +%s)
for i in 0 1 2 3; do
	./createmany -o $M/big/d$i/f $((NBIG / 4)) > /dev/null || { echo "ABORT: createmany"; exit 5; }
done
echo "big: $(ls $M/big/d0 | wc -l) x4 created in $(( $(date +%s) - t0 ))s"
for i in 1 2 3 4 5; do echo data > $M/small/s$i; done
mkdir $M/small/sd && touch $M/small/sd/inner
echo data > $M/big/d0/hl && ln $M/big/d0/hl $M/small/hl
touch $M/big/d0/rin && mv $M/big/d0/rin $M/small/rin
touch $M/small/rout && mv $M/small/rout $M/big/d0/rout
touch $M/small/xskip
sync; sleep 2
echo "changelog records: $M0 $(lfs changelog $M0 | wc -l), $M1 $(lfs changelog $M1 | wc -l)"
echo "hl links: $(lfs fid2path $M $(lfs path2fid $M/small/hl) | tr '\n' ' ')"

# ---- P1 ------------------------------------------------------------------
i=0
p1() {	# p1 <root> args...
	local root=$1; shift
	i=$((i + 1))
	for n in pold pnew; do
		lfs_ $n find $root --since 1h "$@" > $OUT/p1.$i.$n.raw 2> $OUT/p1.$i.$n.err
		echo $? > $OUT/p1.$i.$n.rc
		sort $OUT/p1.$i.$n.raw > $OUT/p1.$i.$n.out
	done
	if cmp -s $OUT/p1.$i.pold.out $OUT/p1.$i.pnew.out &&
	   cmp -s $OUT/p1.$i.pold.err $OUT/p1.$i.pnew.err &&
	   cmp -s $OUT/p1.$i.pold.rc $OUT/p1.$i.pnew.rc; then
		pass "P1.$i [$root --since 1h $*] identical: $(wc -l < $OUT/p1.$i.pnew.out) lines, rc $(cat $OUT/p1.$i.pnew.rc), err[$(tr '\n' '|' < $OUT/p1.$i.pnew.err | cut -c1-160)]"
	else
		bad "P1.$i [$root --since 1h $*] differs"
		diff $OUT/p1.$i.pold.out $OUT/p1.$i.pnew.out | head -5
		diff $OUT/p1.$i.pold.err $OUT/p1.$i.pnew.err | head -5
	fi
}
for root in $M/small $M; do
	p1 $root
	p1 $root -type f
	p1 $root -name 'f*'
	p1 $root ! -name 'x*'
	p1 $root -type d
	p1 $root -printf '%p\n'
	p1 $root -size +0
done
echo "small answer (NEW): $(tr '\n' ' ' < $OUT/p1.1.pnew.out)"
for f in hl rin s1 sd sd/inner xskip; do
	grep -qx "$M/small/$f" $OUT/p1.1.pnew.out && pass "P1 small has $f" || bad "P1 small lost $f"
done
grep -q "/rout$" $OUT/p1.1.pnew.out && bad "P1 small reports rout" || pass "P1 small leaves out rout"

# ---- P2 ------------------------------------------------------------------
mdc_sum() {	# one "name total" line per counter, summed over every mdc
	lctl get_param -n mdc.*.stats | awk '$1 != "snapshot_time" && $1 != "start_time" && $1 != "elapsed_time" {s[$1] += $2} END {for (k in s) print k, s[k]}' | sort
}
rpcs() {	# rpcs <arm> <root>: one run, MDC counter deltas
	mdc_sum > $OUT/mdc.before
	lfs_ $1 find $2 --since 1h > /dev/null 2>&1
	mdc_sum > $OUT/mdc.after
	join $OUT/mdc.before $OUT/mdc.after | awk '$3 - $2 > 0 {printf "%s=%d ", $1, $3 - $2}'
	echo
}
timeit() {	# timeit <arm> <root>: wall seconds of one run
	local s=$(date +%s.%N)
	lfs_ $1 find $2 --since 1h > /dev/null 2>&1
	echo "$(date +%s.%N) - $s" | bc
}
med() { sort -n | awk '{a[NR]=$1} END {printf "median %.3f  range %.3f-%.3f  (n=%d)", (NR % 2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2), a[1], a[NR], NR}'; }
echo "P2 caches: not dropped between runs; one untimed warm-up run per arm first"
for n in pold pnew; do lfs_ $n find $M/small --since 1h > /dev/null 2>&1; done
: > $OUT/t.small.pold; : > $OUT/t.small.pnew
for r in 1 2 3 4 5; do
	for n in pold pnew; do timeit $n $M/small >> $OUT/t.small.$n; done
done
for n in pold pnew; do echo "P2 $M/small $n: $(med < $OUT/t.small.$n)  [$(tr '\n' ' ' < $OUT/t.small.$n)]"; done
for n in pold pnew; do echo "P2 rpcs $M/small $n: $(rpcs $n $M/small)"; done
: > $OUT/t.all.pold; : > $OUT/t.all.pnew
for r in 1 2 3; do
	for n in pold pnew; do timeit $n $M >> $OUT/t.all.$n; done
done
for n in pold pnew; do echo "P2 $M (whole fs) $n: $(med < $OUT/t.all.$n)  [$(tr '\n' ' ' < $OUT/t.all.$n)]"; done
for n in pold pnew; do echo "P2 rpcs $M $n: $(rpcs $n $M)"; done

lctl --device $M0 changelog_deregister $u0
lctl --device $M1 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "PICK RUN DONE"
