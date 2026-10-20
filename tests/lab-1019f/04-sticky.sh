#!/bin/bash
# 10-20 lab f (root, clone VM): R11 A/B.  A cookie in a sticky directory
# that the run cannot rename() over.  Old: prints the matches, then
# "cannot rewrite", every run.  New: refused before anything is printed.
# Run 1 (10-20) found a non-root lfs find --since-cookie fails ENODEV before
# any cookie code (lmv target_obd is in debugfs, /dev/changelog-* is 0600),
# so cookies are seeded by root and chowned, and the non-root case runs
# only with debugfs and the changelog device opened up (a site that grants
# it), restored after; A2/C2 add -o user_fid2path, which a non-root
# --since needs to read the changed objects.  Root without CAP_FOWNER (capsh) is the default-
# config way to reach the same EPERM.
# One fixture for every arm and case; cases only add files.
set -u
OUT=/tmp/lab1019f-sticky; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; D=$M/d; U=nishida
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }

CL=$(lctl --device lfst-MDT0000 changelog_register -n); echo "changelog user $CL"
lctl set_param -n mdd.lfst-MDT0000.changelog_mask=CREAT
mkdir $D && chmod 755 $D && touch $D/base{1..3}; sync; sleep 2
ls -l /dev/changelog-* 2>/dev/null

for a in o t; do
	echo "arm $a ($(cat /tmp/lab1019f-$a.sha)) lfs ld.so: $(LD_PRELOAD=/tmp/arm1019f$a/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 /tmp/lab1019f-$a/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')"
done

# run <arm> <who> <cookie> <label>: who = root | user | nofowner
run() {
	local a=$1 who=$2 ck=$3 lab=$4 rc pre=""
	local L="env LD_PRELOAD=/tmp/arm1019f$a/lib/liblustreapi.so.1 /tmp/lab1019f-$a/lustre/utils/.libs/lfs"
	local before=$(cksum 2>/dev/null < $ck | cut -d' ' -f1)
	case $who in
	user) runuser -u $U -- $L find $D --since-cookie $ck -type f > $OUT/o 2> $OUT/e ;;
	root) $L find $D --since-cookie $ck -type f > $OUT/o 2> $OUT/e ;;
	nofowner) capsh --drop=cap_fowner -- -c "$L find $D --since-cookie $ck -type f" > $OUT/o 2> $OUT/e ;;
	esac
	rc=$?
	local after=$(cksum 2>/dev/null < $ck | cut -d' ' -f1)
	printf '  %-4s %-26s rc=%-3s printed=%-2s cookie %s\n' $a "$lab" $rc \
		$(wc -l < $OUT/o) "$([ "$before" = "$after" ] && echo same || echo CHANGED) ($(stat -c '%U %a' $ck 2>/dev/null))"
	sed 's/^/        out: /' $OUT/o | head -4
	sed 's/^/        err: /' $OUT/e | head -3
}
new() { touch $D/$1-{1..3}; sync; sleep 2; }

seed() {	# seed <arm> <cookie> <owner>
	rm -f $2; run $1 root $2 "seed (root, chown $3)" > /dev/null
	chown $3 $2; chmod 0644 $2
}

echo "##### N: $U, default permissions (expected: ENODEV on both arms)"
for a in o t; do
	seed $a /tmp/job.ck root; new N$a
	run $a user /tmp/job.ck "$U run"
done

echo "##### B: root on its own cookie in /tmp"
for a in o t; do
	seed $a /tmp/job.ck root; new B$a
	run $a root /tmp/job.ck "root run 1"
	run $a root /tmp/job.ck "root run 2"
done

echo "##### D: root over $U's cookie in /tmp (root owns /tmp)"
for a in o t; do
	seed $a /tmp/u.ck $U; new D$a
	run $a root /tmp/u.ck "root run"
done

rm -rf /tmp/stk; mkdir /tmp/stk; chown nobody /tmp/stk; chmod 1777 /tmp/stk
ls -ld /tmp/stk
echo "##### E: root over $U's cookie in nobody's 1777 dir (CAP_FOWNER)"
for a in o t; do
	seed $a /tmp/stk/c.ck $U; new E$a
	run $a root /tmp/stk/c.ck "root run"
done

echo "##### F: same, root WITHOUT CAP_FOWNER (the kernel refuses the rename)"
for a in o t o t; do
	seed $a /tmp/stk/c.ck $U; new F$a$RANDOM
	run $a nofowner /tmp/stk/c.ck "root -cap_fowner run 1"
	run $a nofowner /tmp/stk/c.ck "root -cap_fowner run 2"
done

echo "##### G: root WITHOUT CAP_FOWNER, its own cookie there (owner passes)"
for a in o t; do
	seed $a /tmp/stk/c.ck root; new G$a
	run $a nofowner /tmp/stk/c.ck "root -cap_fowner run"
done

echo "##### open debugfs and the changelog device to $U"
DM=$(stat -c %a /sys/kernel/debug); CM=$(stat -c %a /dev/changelog-lfst-MDT0000)
chmod 755 /sys/kernel/debug; chmod 644 /dev/changelog-lfst-MDT0000
runuser -u $U -- lctl get_param -n lmv.*.target_obd 2>&1 | head -2

echo "##### A: root-seeded /tmp/job.ck 0644, $U runs twice (the lreview case)"
for a in o t o t; do
	seed $a /tmp/job.ck root; new A$a$RANDOM
	run $a user /tmp/job.ck "$U run 1"
	run $a user /tmp/job.ck "$U run 2"
done

echo "##### C: $U on its own cookie in /tmp"
for a in o t; do
	seed $a /tmp/u.ck $U; new C$a
	run $a user /tmp/u.ck "$U run 1"
	run $a user /tmp/u.ck "$U run 2"
done

echo "##### remount the client with -o user_fid2path"
SPEC=$(mount -t lustre | awk -v m=$M '$3 == m {print $1}')
umount $M && mount -t lustre -o user_fid2path $SPEC $M
mount -t lustre | grep " $M "
chmod 644 /dev/changelog-lfst-MDT0000	# the remount made it anew, 0600

echo "##### A2: as A, with user_fid2path"
for a in o t o t; do
	seed $a /tmp/job.ck root; new A2$a$RANDOM
	run $a user /tmp/job.ck "$U run 1"
	run $a user /tmp/job.ck "$U run 2"
done

echo "##### C2: as C, with user_fid2path"
for a in o t; do
	seed $a /tmp/u.ck $U; new C2$a
	run $a user /tmp/u.ck "$U run 1"
	run $a user /tmp/u.ck "$U run 2"
done

chmod $DM /sys/kernel/debug; chmod $CM /dev/changelog-lfst-MDT0000
echo "restored: $(stat -c %a /sys/kernel/debug) $(stat -c %a /dev/changelog-lfst-MDT0000)"

rm -rf /tmp/stk /tmp/job.ck /tmp/u.ck
lctl --device lfst-MDT0000 changelog_deregister $CL
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
