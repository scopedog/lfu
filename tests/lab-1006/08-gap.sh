#!/bin/bash
# 10-06 lab, stage 8 (as root on the clone VM): the --since gap warning.
# OLD = a1006-pushed 6e26f11543 (/tmp/lab1006-gold), NEW = 29b286be44
# (/tmp/lab1006-gnew), "find --since, warn when the log was cleared".
# ldiskfs DNE fixture (FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2), one registered
# user on each MDT and no other.
#
# G3f: fresh log (record 1 present): --since 1h, NEW no warning.
# G1:  f0, clear past it on MDT0, f1: --since 1h, NEW warns, stdout == OLD.
# G4:  MDT1 cleared to empty, nothing written: no warning, no error.
# G2:  --changelog MDT0 --since 1 warns; --since <oldest> does not.
# G3:  --since @now: no warning.
# G5:  --since-cookie: NEW == OLD, stale -ESTALE unchanged, no gap warning.
set -u
OUT=/tmp/lab1006-gap; M=/mnt/lfst; M0=lfst-MDT0000; M1=lfst-MDT0001
W="cleared past the --since anchor"
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LUSTRE=/tmp/lab1006-$n/lustre LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 /tmp/lab1006-$n/lustre/utils/.libs/lfs "$@"; }
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; }
# run both arms; leaves $OUT/<tag>.<arm>.{out,err,rc}
both() {
	local tag=$1; shift
	for n in gold gnew; do
		lfs_ $n "$@" > $OUT/$tag.$n.out 2> $OUT/$tag.$n.err
		echo $? > $OUT/$tag.$n.rc
		echo "$tag $n rc=$(cat $OUT/$tag.$n.rc) out=$(wc -l < $OUT/$tag.$n.out) err[$(tr '\n' '|' < $OUT/$tag.$n.err | cut -c1-300)]"
	done
}
warned() { grep -q "$W" $OUT/$1.$2.err; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for n in gold gnew; do
	l=$(LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1006-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')
	echo "$n lfs loads:$l  gap-string=$(strings /tmp/arm1006$n/lib/liblustreapi.so.1 | grep -c "$W")"
	echo "$l" | grep -q "/tmp/arm1006$n/lib/liblustreapi.so.1" || { echo "ABORT: $n loads the wrong liblustreapi"; exit 3; }
done
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
u0=$(lctl --device $M0 changelog_register -n)
u1=$(lctl --device $M1 changelog_register -n)
echo "users: $M0 [$(lctl get_param -n mdd.$M0.changelog_users | grep -c '^cl')] $u0, $M1 [$(lctl get_param -n mdd.$M1.changelog_users | grep -c '^cl')] $u1"
first() { lfs changelog $1 | head -1 | awk '{print $1}'; }

# ---- G3f: fresh log ------------------------------------------------------
lfs mkdir -i 0 $M/m0 && lfs mkdir -i 1 $M/m1 || { echo "ABORT: mkdir"; exit 5; }
touch $M/m0/fresh $M/m1/fresh; sync; sleep 2
echo "fresh: $M0 first=$(first $M0), $M1 first=$(first $M1)"
both g3f find $M --since 1h
[ "$(first $M0)" = 1 ] && ! warned g3f gnew && pass "G3f fresh log, no warning" || bad "G3f"

# ---- G1 / G4 -------------------------------------------------------------
touch $M/m0/f0; sync
last0=$(lfs changelog $M0 | tail -1 | awk '{print $1}')
lfs changelog_clear $M0 $u0 $last0
lfs changelog_clear $M1 $u1 0
touch $M/m0/f1; sync; sleep 2
o0=$(first $M0)
echo "after clear: $M0 cleared to $last0, first=$o0; $M1 records=$(lfs changelog $M1 | wc -l)"
both g1 find $M --since 1h
! warned g1 gold && warned g1 gnew && pass "G1 OLD silent, NEW warns" || bad "G1 warning"
grep -q "'$M0'.*$W.*oldest record is $o0, from " $OUT/g1.gnew.err && pass "G1 names $M0 and index $o0" || bad "G1 text"
[ "$(cat $OUT/g1.gold.rc)$(cat $OUT/g1.gnew.rc)" = 00 ] && pass "G1 rc 0 both" || bad "G1 rc"
cmp -s $OUT/g1.gold.out $OUT/g1.gnew.out && pass "G1 stdout identical" || { bad "G1 stdout differs"; diff $OUT/g1.gold.out $OUT/g1.gnew.out | head; }
grep -q "'$M1'" $OUT/g1.gnew.err && bad "G4 warned about empty $M1" || pass "G4 empty $M1: no warning"
grep -qi "error\|cannot" $OUT/g1.gnew.err && bad "G4 an error on stderr" || pass "G4 no error"

# ---- G2 ------------------------------------------------------------------
both g2a find $M --changelog $M0 --since 1
! warned g2a gold && warned g2a gnew && pass "G2 --since 1: OLD silent, NEW warns" || bad "G2 --since 1"
both g2b find $M --changelog $M0 --since $o0
! warned g2b gnew && pass "G2 --since $o0 (the oldest): no warning" || bad "G2 --since oldest"
both g2c find $M --changelog $M0 --since $((o0 - 1))
warned g2c gnew && pass "G2 --since $((o0 - 1)) (one before): warns" || bad "G2 --since oldest-1"

# ---- G3 ------------------------------------------------------------------
both g3 find $M --since @$(date +%s)
! warned g3 gnew && pass "G3 --since @now: no warning" || bad "G3"

# ---- G5: cookie, the 160Ac stale construction ----------------------------
for n in gold gnew; do rm -f $OUT/ck.$n; done
for n in gold gnew; do lfs_ $n find $M --since-cookie $OUT/ck.$n -type f > $OUT/g5a.$n.out 2> $OUT/g5a.$n.err; echo "G5 first $n rc=$? out=$(wc -l < $OUT/g5a.$n.out) err[$(tr '\n' '|' < $OUT/g5a.$n.err)]"; done
cmp -s $OUT/ck.gold $OUT/ck.gnew && echo "  cookies identical" || { echo "  cookies differ:"; diff $OUT/ck.gold $OUT/ck.gnew; }
touch $M/m0/g1; sync
lastg=$(lfs changelog $M0 | tail -1 | awk '{print $1}')
lfs changelog_clear $M0 $u0 $lastg
touch $M/m0/g2; sync; sleep 1
echo "G5 purged $M0 to $lastg, first now $(first $M0)"
for n in gold gnew; do cp $OUT/ck.$n $OUT/ck.$n.before; done
for n in gold gnew; do
	lfs_ $n find $M --since-cookie $OUT/ck.$n -type f > $OUT/g5.$n.out 2> $OUT/g5.$n.err
	echo $? > $OUT/g5.$n.rc
	echo "G5 stale $n rc=$(cat $OUT/g5.$n.rc) out=$(wc -l < $OUT/g5.$n.out) err[$(tr '\n' '|' < $OUT/g5.$n.err)]"
done
[ "$(cat $OUT/g5.gold.rc)" = "$(cat $OUT/g5.gnew.rc)" ] && [ "$(cat $OUT/g5.gnew.rc)" != 0 ] && pass "G5 both refuse, same rc" || bad "G5 rc"
# the cookie path is each arm's own; compare with it normalised
for n in gold gnew; do sed "s|ck\.$n|ck.ARM|g" $OUT/g5.$n.err > $OUT/g5.$n.errn; done
cmp -s $OUT/g5.gold.errn $OUT/g5.gnew.errn && pass "G5 stderr identical (cookie name normalised)" || { bad "G5 stderr differs"; diff $OUT/g5.gold.errn $OUT/g5.gnew.errn; }
grep -q -i "stale\|purged" $OUT/g5.gnew.err && pass "G5 the stale message" || bad "G5 no stale message"
! warned g5 gnew && ! warned g5a gnew && pass "G5 no gap warning on the cookie path" || bad "G5 gap warning"
for n in gold gnew; do cmp -s $OUT/ck.$n $OUT/ck.$n.before && echo "  $n cookie left as it was" || echo "  $n cookie CHANGED"; done

lctl --device $M0 changelog_deregister $u0
lctl --device $M1 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "PASS $(grep -c '^PASS' $OUT/run.txt) FAIL $(grep -c '^FAIL' $OUT/run.txt)"
echo "== end $(date '+%F %T')"
echo "GAP RUN DONE"
