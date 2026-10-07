#!/bin/bash
# 10-06 lab, stage 16 (as root on the clone VM): FINAL = nfin 2848d7f2cf,
# which no longer gives the filter STATX_NLINK for a directory.  Arms:
# BASE = nbase ceaeec5973 (no pick), NEW = nnew f14b3b09ab (pick with
# nlink, directories included), FINAL = nfin 2848d7f2cf.
# ldiskfs DNE fixture (FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2), one registered
# user on each MDT.
#
# N1: answers byte-identical (stdout, stderr, rc), BASE vs FINAL and NEW vs
#     FINAL, same fixture and 14 queries as P1 of 11-pick.sh.
# N2: cost of `lfs find $M/small --since 1h`, three arms alternated, 5 runs
#     each, wall time and MDC RPC deltas; whole fs 3 each.
# D:  then 2000 directories outside the subtree, each holding a subdir:
#     the RPC deltas again, and the identity of the small answer.
# N3: FINAL's llapi_scan_test -t 17 on the mount.
set -u
OUT=/tmp/lab1006-final; M=/mnt/lfst; M0=lfst-MDT0000; M1=lfst-MDT0001
NBIG=${NBIG:-20000}
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 /tmp/lab1006-$n/lustre/utils/.libs/lfs "$@"; }
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for n in nbase nnew nfin; do
	l=$(LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1006-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')
	echo "$n ($(cat /tmp/lab1006-$n.sha)) lfs loads:$l  pre_cb=$(nm /tmp/lab1006-$n/lustre/utils/.libs/liblustreapi.so.1 2>/dev/null | grep -c find_since_pre_cb) nlink-in-scan_fid=$(grep -c 'STATX_TYPE | STATX_NLINK' /tmp/lab1006-$n/lustre/utils/liblustreapi_scan.c)"
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

# ---- N1 ------------------------------------------------------------------
i=0
same() {	# same <a> <b>: all three files identical
	cmp -s $OUT/n1.$i.$1.out $OUT/n1.$i.$2.out &&
	cmp -s $OUT/n1.$i.$1.err $OUT/n1.$i.$2.err &&
	cmp -s $OUT/n1.$i.$1.rc $OUT/n1.$i.$2.rc
}
n1() {	# n1 <root> args...
	local root=$1; shift
	i=$((i + 1))
	for n in nbase nnew nfin; do
		lfs_ $n find $root --since 1h "$@" > $OUT/n1.$i.$n.raw 2> $OUT/n1.$i.$n.err
		echo $? > $OUT/n1.$i.$n.rc
		sort $OUT/n1.$i.$n.raw > $OUT/n1.$i.$n.out
	done
	if same nbase nfin && same nnew nfin; then
		pass "N1.$i [$root --since 1h $*] identical x3: $(wc -l < $OUT/n1.$i.nnew.out) lines, rc $(cat $OUT/n1.$i.nnew.rc), err[$(tr '\n' '|' < $OUT/n1.$i.nnew.err | cut -c1-160)]"
	else
		same nbase nfin || { bad "N1.$i [$root $*] BASE != FINAL"; diff $OUT/n1.$i.nbase.out $OUT/n1.$i.nfin.out | head -5; diff $OUT/n1.$i.nbase.err $OUT/n1.$i.nfin.err | head -5; }
		same nnew nfin || { bad "N1.$i [$root $*] NEW != FINAL"; diff $OUT/n1.$i.nnew.out $OUT/n1.$i.nfin.out | head -5; diff $OUT/n1.$i.nnew.err $OUT/n1.$i.nfin.err | head -5; }
	fi
}
for root in $M/small $M; do
	n1 $root
	n1 $root -type f
	n1 $root -name 'f*'
	n1 $root ! -name 'x*'
	n1 $root -type d
	n1 $root -printf '%p\n'
	n1 $root -size +0
done
echo "small answer (FINAL): $(tr '\n' ' ' < $OUT/n1.1.nfin.out)"
for f in hl rin s1 sd sd/inner xskip; do
	grep -qx "$M/small/$f" $OUT/n1.1.nfin.out && pass "N1 small has $f" || bad "N1 small lost $f"
done
grep -q "/rout$" $OUT/n1.1.nfin.out && bad "N1 small reports rout" || pass "N1 small leaves out rout"

# ---- N2 ------------------------------------------------------------------
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
echo "N2 caches: not dropped between runs; one untimed warm-up run per arm first"
for n in nbase nnew nfin; do lfs_ $n find $M/small --since 1h > /dev/null 2>&1; done
: > $OUT/t.small.nbase; : > $OUT/t.small.nnew; : > $OUT/t.small.nfin
for r in 1 2 3 4 5; do
	for n in nbase nnew nfin; do timeit $n $M/small >> $OUT/t.small.$n; done
done
for n in nbase nnew nfin; do echo "N2 $M/small $n: $(med < $OUT/t.small.$n)  [$(tr '\n' ' ' < $OUT/t.small.$n)]"; done
for n in nbase nnew nfin; do echo "N2 rpcs $M/small $n: $(rpcs $n $M/small)"; done
: > $OUT/t.all.nbase; : > $OUT/t.all.nnew; : > $OUT/t.all.nfin
for r in 1 2 3; do
	for n in nbase nnew nfin; do timeit $n $M >> $OUT/t.all.$n; done
done
for n in nbase nnew nfin; do echo "N2 $M (whole fs) $n: $(med < $OUT/t.all.$n)  [$(tr '\n' ' ' < $OUT/t.all.$n)]"; done
for n in nbase nnew nfin; do echo "N2 rpcs $M $n: $(rpcs $n $M)"; done

# ---- D: directories outside the subtree ----------------------------------
lfs mkdir -i 0 $M/bigd || { echo "ABORT: mkdir bigd"; exit 6; }
t0=$(date +%s)
for j in $(seq 1 2000); do mkdir $M/bigd/d$j && mkdir $M/bigd/d$j/sub; done
echo "D: 2000 dirs + 2000 subdirs in $(( $(date +%s) - t0 ))s; d1 nlink $(stat -c %h $M/bigd/d1)"
sync; sleep 2
for n in nbase nnew nfin; do lfs_ $n find $M/small --since 1h > /dev/null 2>&1; done
for n in nbase nnew nfin; do echo "D rpcs $M/small $n: $(rpcs $n $M/small)"; done
: > $OUT/t.d.nbase; : > $OUT/t.d.nnew; : > $OUT/t.d.nfin
for r in 1 2 3; do
	for n in nbase nnew nfin; do timeit $n $M/small >> $OUT/t.d.$n; done
done
for n in nbase nnew nfin; do echo "D $M/small $n: $(med < $OUT/t.d.$n)  [$(tr '\n' ' ' < $OUT/t.d.$n)]"; done
i=100
n1 $M/small
n1 $M/small -type d
n1 $M -type d

# ---- N3 ------------------------------------------------------------------
mkdir -p $M/n3 && env LD_PRELOAD=/tmp/arm1006nfin/lib/liblustreapi.so.1 \
	/tmp/lab1006-nfin/lustre/tests/.libs/llapi_scan_test -d $M/n3 -t 17 > $OUT/n3.txt 2>&1
rc=$?; tail -5 $OUT/n3.txt
[ $rc = 0 ] && pass "N3 llapi_scan_test -t 17 (FINAL) rc 0" || bad "N3 llapi_scan_test -t 17 rc $rc"
rm -rf $M/n3

lctl --device $M0 changelog_deregister $u0
lctl --device $M1 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "FINAL RUN DONE"
