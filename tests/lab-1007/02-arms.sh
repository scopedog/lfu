#!/bin/bash
# 10-07 lab, stage 2 (as root on the clone VM): A/B arms on an ldiskfs DNE
# fixture (FSNAME=lfst, MDSCOUNT=2 OSTCOUNT=2), installed framework and
# modules.  Each arm runs its own tree's lfs with its own liblustreapi
# (LD_PRELOAD, asserted).
#
# C1 (68419): a cookie that is a symlink, live or dangling, is refused and
#             the link is left alone.
# L1 (68417): lfs find --local --since says "needs a changelog" once, not
#             once per local target.
# E1 (68415): test8's new source assertions fail on OLD's library and pass
#             on NEW's -- the same NEW test binary, the library swapped.
set -u
OUT=/tmp/lab1007-arms; M=/mnt/lfst
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 /tmp/lab1007-$n/lustre/utils/.libs/lfs "$@"; }
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for n in old new; do
	l=$(LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1007-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')
	echo "$n lfs loads:$l"
	echo "$l" | grep -q "/tmp/arm1007$n/lib/liblustreapi.so.1" || { echo "ABORT: $n loads the wrong liblustreapi"; exit 3; }
done
cmp -s /tmp/arm1007old/lib/liblustreapi.so.1 /tmp/arm1007new/lib/liblustreapi.so.1 && { echo "ABORT: the arms' libraries are identical"; exit 3; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }

u0=$(lctl --device lfst-MDT0000 changelog_register -n)
u1=$(lctl --device lfst-MDT0001 changelog_register -n)
echo "changelog users: $u0 $u1"
mkdir -p $M/c; echo x > $M/c/f1; sync; sleep 2

# ---- C1 -----------------------------------------------------------------
for n in old new; do
	D=$OUT/c1.$n; mkdir -p $D
	# a real cookie, written by a run, then a link to it
	lfs_ $n find $M --since-cookie $D/real -type f > /dev/null 2>&1 ||
		echo "  $n: first run to make the cookie failed"
	cp $D/real $D/real.orig
	ln -s real $D/link
	lfs_ $n find $M --since-cookie $D/link -type f > $D/live.out 2> $D/live.err
	rc=$?
	if [ -L $D/link ]; then lk=link; else lk=REPLACED; fi
	cmp -s $D/real $D/real.orig && tg=unchanged || tg=CHANGED
	echo "C1 live $n rc=$rc link=$lk target=$tg err[$(head -2 $D/live.err | tr '\n' '|')]"
	eval "c1l_$n='$rc $lk'"
	# a dangling one
	ln -s nowhere $D/dang
	lfs_ $n find $M --since-cookie $D/dang -type f > $D/dang.out 2> $D/dang.err
	rc=$?
	if [ -L $D/dang ]; then lk=link; else lk=REPLACED; fi
	echo "C1 dangling $n rc=$rc link=$lk lines=$(wc -l < $D/dang.out) err[$(head -2 $D/dang.err | tr '\n' '|')]"
	eval "c1d_$n='$rc $lk'"
done
[ "$c1l_new" != "${c1l_new#[1-9]}" ] && [ "${c1l_new#* }" = link ] &&
	grep -q "not a regular file" $OUT/c1.new/live.err &&
	pass "C1 new refuses a live link and keeps it" || bad "C1 new live: $c1l_new"
[ "$c1d_new" != "${c1d_new#[1-9]}" ] && [ "${c1d_new#* }" = link ] &&
	grep -q "not a regular file" $OUT/c1.new/dang.err &&
	pass "C1 new refuses a dangling link and keeps it" || bad "C1 new dangling: $c1d_new"
echo "  C1 old: live [$c1l_old] dangling [$c1d_old] (expected 0 REPLACED for the defect)"
# control: a plain cookie still works in NEW
lfs_ new find $M --since-cookie $OUT/c1.new/plain -type f > /dev/null 2>&1 &&
	[ -f $OUT/c1.new/plain ] && pass "C1 new plain cookie still written" ||
	bad "C1 new plain cookie"

# ---- L1 -----------------------------------------------------------------
for n in old new; do
	lfs_ $n find --local --since 1h > $OUT/l1.$n.out 2> $OUT/l1.$n.err
	rc=$?
	k=$(grep -c "needs a changelog" $OUT/l1.$n.err)
	echo "L1 $n rc=$rc 'needs a changelog' x$k, stderr lines $(wc -l < $OUT/l1.$n.err), stdout $(wc -l < $OUT/l1.$n.out)"
	eval "l1_$n=$k; l1rc_$n=$rc"
done
[ "$l1_new" = 1 ] && [ "$l1rc_new" != 0 ] && pass "L1 new refuses once" || bad "L1 new: x$l1_new rc=$l1rc_new"
for o in "--since-cookie $OUT/l1.ck" "--changelog all"; do
	lfs_ new find --local $o > /dev/null 2> $OUT/l1b.err
	rc=$?
	echo "L1 new [$o] rc=$rc x$(grep -c 'needs a changelog' $OUT/l1b.err) [$(head -1 $OUT/l1b.err)]"
done
[ ! -e $OUT/l1.ck ] && pass "L1 --since-cookie refused before the cookie was touched" || bad "L1 cookie written"

# ---- E1 -----------------------------------------------------------------
T8=/tmp/lab1007-new/lustre/tests/.libs/llapi_scan_changelog_test
# as 56Eea sets it up: the directory on MDT0000, a -m ALL user
e1d=$M/llapi_scan_changelog_test.d
rm -rf $e1d; lfs mkdir -i 0 $e1d && lfs setdirstripe -D -i 0 -c 1 $e1d ||
	echo "E1 setup of $e1d failed"
ue=$(lctl --device lfst-MDT0000 changelog_register -m ALL -n)
for n in old new; do
	env LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 $T8 -m lfst-MDT0000 \
		-d $M -u $ue -o 8 > $OUT/e1.$n.txt 2>&1
	rc=$?
	echo "E1 new test8 on $n's library rc=$rc [$(grep -m2 -E 'carry|FAIL|failed|PASS|delivered' $OUT/e1.$n.txt | tr '\n' '|')]"
	eval "e1_$n=$rc"
done
[ "$e1_new" = 0 ] && pass "E1 test8 passes on NEW" || bad "E1 test8 fails on NEW"
[ "$e1_old" != 0 ] && grep -q "carry a source" $OUT/e1.old.txt && pass "E1 test8 catches OLD" || bad "E1 test8 did not catch OLD"

rm -rf $e1d
lctl --device lfst-MDT0000 changelog_deregister $ue
lctl --device lfst-MDT0000 changelog_deregister $u0
lctl --device lfst-MDT0001 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "PASS $(grep -c '^PASS' $OUT/run.txt)  FAIL $(grep -c '^FAIL' $OUT/run.txt)"
echo "== end $(date '+%F %T')"
echo "ARMS DONE"
