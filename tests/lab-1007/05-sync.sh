#!/bin/bash
# 10-07 lab, stage 5 (as root on the clone VM): F1 (68419), --since-cookie
# fsync()s stdout when it is a regular file, before the cookie is renamed,
# and does not fail on a pipe.  OLD = /tmp/lab1007-old, NEW = $1 (new3).
set -u
NEW=${1:-new3}
OUT=/tmp/lab1007-sync; M=/mnt/lfst
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
lfs_() { local n=$1; shift; env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 /tmp/lab1007-$n/lustre/utils/.libs/lfs "$@"; }
echo "== start $(date '+%F %T') NEW=$NEW ($(cat /tmp/lab1007-$NEW.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }
u0=$(lctl --device lfst-MDT0000 changelog_register -n)
u1=$(lctl --device lfst-MDT0001 changelog_register -n)
mkdir -p $M/s; for i in 1 2 3; do echo x > $M/s/f$i; done; sync; sleep 2

for n in old $NEW; do
	# a regular file: the matches are synced, then the cookie is renamed
	strace -f -e trace=fsync,rename,renameat,renameat2 -o $OUT/st.$n \
		bash -c "env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 /tmp/lab1007-$n/lustre/utils/.libs/lfs find $M --since-cookie $OUT/ck.$n -type f > $OUT/out.$n"
	rc=$?
	echo "F1 file $n rc=$rc lines=$(wc -l < $OUT/out.$n) fsync(1)=$(grep -c 'fsync(1)' $OUT/st.$n) order: $(grep -oE 'fsync\([0-9]+\)|rename[a-z0-9]*\(' $OUT/st.$n | tr '\n' ' ')"
	# a pipe: nothing to sync, and no error
	rm -f $OUT/ck.$n.p
	lfs_ $n find $M --since-cookie $OUT/ck.$n.p -type f | cat > $OUT/pipe.$n
	echo "F1 pipe $n rc=${PIPESTATUS[0]} lines=$(wc -l < $OUT/pipe.$n) cookie=$([ -s $OUT/ck.$n.p ] && echo written || echo MISSING)"
done
first=$(grep -oE 'fsync\(1\)|rename[a-z0-9]*\(' $OUT/st.$NEW | head -1)
[ "$first" = "fsync(1)" ] && echo "PASS F1 new syncs stdout before the rename" || echo "FAIL F1 new: first is [$first]"
grep -q 'fsync(1)' $OUT/st.old && echo "  F1 old syncs stdout too?" || echo "  F1 old does not sync stdout (expected)"
grep -q "pipe $NEW rc=0 .* cookie=written" $OUT/run.txt && echo "PASS F1 pipe unaffected" || echo "FAIL F1 pipe"

lctl --device lfst-MDT0000 changelog_deregister $u0
lctl --device lfst-MDT0001 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "SYNC DONE"
