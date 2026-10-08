#!/bin/bash
# 10-07 lab, stage 6 (as root on the clone VM): D1 (gap follow-up), a caller
# who cannot read the changelog sees each error once, not twice.  A = new3
# (probe before the scan), B = new4 (probe after it).
set -u
OUT=/tmp/lab1007-dup; M=/mnt/lfst
rm -rf $OUT; mkdir -p $OUT; chmod 755 $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }
u0=$(lctl --device lfst-MDT0000 changelog_register -n)
u1=$(lctl --device lfst-MDT0001 changelog_register -n)
mkdir -p $M/d; chmod 777 $M/d; echo x > $M/d/f; sync; sleep 2
for n in new3 new4; do
	runuser -u nishida -- env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 \
		/tmp/lab1007-$n/lustre/utils/.libs/lfs find $M --since 1h > $OUT/$n.out 2> $OUT/$n.err
	rc=$?
	echo "D1 $n rc=$rc stderr lines=$(wc -l < $OUT/$n.err)"; sed 's/^/    /' $OUT/$n.err
	# and as root the warning still comes, after a clear
done
for n in new3 new4; do
	env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 \
		/tmp/lab1007-$n/lustre/utils/.libs/lfs find $M --since 1h > /dev/null 2> $OUT/$n.root.err
	echo "D1 root $n rc=$? stderr: $(tr '\n' '|' < $OUT/$n.root.err)"
done
a=$(wc -l < $OUT/new3.err); b=$(wc -l < $OUT/new4.err)
[ $b -lt $a ] && [ $b -gt 0 ] && echo "PASS D1 new4 says less ($b < $a lines)" || echo "FAIL D1 new3=$a new4=$b"
lctl --device lfst-MDT0000 changelog_deregister $u0
lctl --device lfst-MDT0001 changelog_deregister $u1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "DUP DONE"
