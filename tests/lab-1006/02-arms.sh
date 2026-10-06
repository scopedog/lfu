#!/bin/bash
# 10-06 lab, stage 2 (as root on the clone VM): A/B arms M1, D1, S1 on an
# ldiskfs DNE fixture (FSNAME=lfst, MDSCOUNT=2 OSTCOUNT=2), installed
# framework and modules.  Each arm runs its own tree's lfs with its own
# liblustreapi (LD_PRELOAD, asserted).
#
# M1 (68417): --since --mdt N equals the walk's --mdt N on the changed files.
# D1 (68418): --changelog all --maxdepth 0 is refused.
# S1 (68417): --since ' -5' / ' +5' is refused; the good spellings are not.
set -u
OUT=/tmp/lab1006-arms; M=/mnt/lfst
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LUSTRE=/tmp/lab1006-$n/lustre LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 /tmp/lab1006-$n/lustre/utils/.libs/lfs "$@"; }
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for n in old new; do
	l=$(LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1006-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')
	echo "$n lfs loads:$l"
	echo "$l" | grep -q "/tmp/arm1006$n/lib/liblustreapi.so.1" || { echo "ABORT: $n loads the wrong liblustreapi"; exit 3; }
done
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
lfs mdts $M

u0=$(lctl --device lfst-MDT0000 changelog_register -n)
u1=$(lctl --device lfst-MDT0001 changelog_register -n)
echo "changelog users: $u0 $u1"

# ---- M1 -----------------------------------------------------------------
lfs mkdir -i 0 $M/m0 && lfs mkdir -i 1 $M/m1 || { echo "ABORT: mkdir"; exit 5; }
for d in m0 m1; do for i in 1 2 3 4 5; do echo x > $M/$d/f$i; done; done
sync; sleep 2
echo "m0 on $(lfs getdirstripe -m $M/m0), m1 on $(lfs getdirstripe -m $M/m1)"
for i in 0 1; do
	lfs find $M/m0 $M/m1 --mdt $i | sort > $OUT/walk.mdt$i
	for n in old new; do
		lfs_ $n find $M --since 1h --mdt $i 2> $OUT/m1.$n.mdt$i.err |
			grep -E "^$M/m[01](/|$)" | sort > $OUT/since.$n.mdt$i
		echo "M1 --mdt $i: walk $(wc -l < $OUT/walk.mdt$i), $n --since $(wc -l < $OUT/since.$n.mdt$i) err[$(head -2 $OUT/m1.$n.mdt$i.err | tr '\n' '|')]"
	done
	cmp -s $OUT/walk.mdt$i $OUT/since.new.mdt$i && pass "M1 new == walk on --mdt $i" || { bad "M1 new != walk on --mdt $i"; diff $OUT/walk.mdt$i $OUT/since.new.mdt$i | head; }
	cmp -s $OUT/walk.mdt$i $OUT/since.old.mdt$i && echo "  M1 old == walk on --mdt $i" || echo "  M1 old != walk on --mdt $i (expected for the defect)"
done
# a negation as well
lfs find $M/m0 $M/m1 ! --mdt 1 | sort > $OUT/walk.nmdt1
for n in old new; do
	lfs_ $n find $M --since 1h ! --mdt 1 2>/dev/null | grep -E "^$M/m[01](/|$)" | sort > $OUT/since.$n.nmdt1
	echo "M1 ! --mdt 1: walk $(wc -l < $OUT/walk.nmdt1), $n $(wc -l < $OUT/since.$n.nmdt1)"
done
cmp -s $OUT/walk.nmdt1 $OUT/since.new.nmdt1 && pass "M1 new == walk on ! --mdt 1" || bad "M1 new != walk on ! --mdt 1"

# ---- D1 -----------------------------------------------------------------
for extra in "" "--resolve"; do
	for n in old new; do
		lfs_ $n find $M --changelog all --since 1h --maxdepth 0 $extra > $OUT/d1.$n.out 2> $OUT/d1.$n.err
		rc=$?
		echo "D1 [$extra] $n rc=$rc lines=$(wc -l < $OUT/d1.$n.out) err[$(head -2 $OUT/d1.$n.err | tr '\n' '|')]"
		eval "d1_$n=$rc"
	done
	[ $d1_new -ne 0 ] && grep -q "describe a walk" $OUT/d1.new.err && pass "D1 [$extra] new refuses" || bad "D1 [$extra] new did not refuse"
done
# --maxdepth 1 and a plain --changelog: unchanged in both
for n in old new; do
	lfs_ $n find $M --changelog all --since 1h > $OUT/d1b.$n.out 2>&1
	echo "D1 control (no depth) $n rc=$? lines=$(wc -l < $OUT/d1b.$n.out)"
done
cmp -s $OUT/d1b.old.out $OUT/d1b.new.out && pass "D1 control arms agree" || bad "D1 control arms differ"
# the walk-side --since keeps --maxdepth 0
for n in old new; do
	lfs_ $n find $M --since 1h --maxdepth 0 > $OUT/d1c.$n.out 2>&1
	echo "D1 --since --maxdepth 0 $n rc=$? [$(head -2 $OUT/d1c.$n.out | tr '\n' '|')]"
done

# ---- S1 -----------------------------------------------------------------
for v in " -5" " +5" "-5" "+5"; do
	for n in old new; do
		lfs_ $n find $M --changelog lfst-MDT0000 --since "$v" > $OUT/s1.$n.out 2> $OUT/s1.$n.err
		rc=$?
		echo "S1 '$v' $n rc=$rc lines=$(wc -l < $OUT/s1.$n.out) err[$(head -1 $OUT/s1.$n.err)]"
		eval "s1_$n=$rc"
	done
	[ $s1_new -ne 0 ] && grep -q "bad --since" $OUT/s1.new.err && pass "S1 '$v' new refuses" || bad "S1 '$v' new accepts"
done
now=$(date +%s)
for v in 1 2h "@$((now - 60))" 00:00 "$(date +%F) 00:00" "$(date +%F)T00:00:00"; do
	for n in old new; do
		lfs_ $n find $M --changelog lfst-MDT0000 --since "$v" > $OUT/s1g.$n.out 2> $OUT/s1g.$n.err
		eval "rc_$n=$?"
	done
	echo "S1 good '$v': old rc=$rc_old lines=$(wc -l < $OUT/s1g.old.out), new rc=$rc_new lines=$(wc -l < $OUT/s1g.new.out) err[$(head -1 $OUT/s1g.new.err)]"
	[ $rc_new = 0 ] && cmp -s $OUT/s1g.old.out $OUT/s1g.new.out && pass "S1 '$v' accepted, arms agree" || bad "S1 '$v'"
done

lctl --device lfst-MDT0000 changelog_deregister $u0
lctl --device lfst-MDT0001 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "ARMS DONE"
