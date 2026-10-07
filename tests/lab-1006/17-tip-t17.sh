#!/bin/bash
# 10-06 lab, stage 17 (as root on the clone VM): llapi_scan_test -t 17 from
# the tip 036735e9fb (/tmp/lab1006-ntip: nfin's build with the tip's test
# source rebuilt; the library is nfin's, its sources are the same but for
# a pfind.c comment).  Usage: 17-tip-t17.sh ldiskfs|zfs
set -u
FS=${1:-ldiskfs}; OUT=/tmp/lab1006-tip17-$FS
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') $FS ($(cat /tmp/lab1006-ntip.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
if [ $FS = zfs ]; then
	export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=2 TMP=/tmp/zfslab17
	rm -rf $TMP; mkdir -p $TMP; M=/mnt/zfst
else
	export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2; M=/mnt/lfst
fi
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
B=/tmp/lab1006-ntip/lustre/tests/.libs/llapi_scan_test
echo "binary loads: $(LD_TRACE_LOADED_OBJECTS=1 $B | grep lustreapi | tr -s ' \t' ' ')"
grep -c "fp_nlink == 2\|nlink == 2" /tmp/lab1006-ntip/lustre/tests/llapi_scan_test.c | sed 's/^/nlink==2 asserts in source: /'
mkdir -p $M/t17
$B -d $M/t17 -t 17; rc=$?
echo "T17 RC=$rc"
rm -rf $M/t17
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
[ $FS = zfs ] && rm -rf $TMP
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
