#!/bin/bash
# 10-07 lab, stage 4 (as root on the clone VM): an arm's sanity 56E* + 160A*,
# with NEW's lfs, liblustreapi and test binaries bound over the installed
# ones for this run only.  Usage: 13-sanity.sh <arm> ldiskfs|zfs
set -u
ARM=$1; FS=${2:-ldiskfs}
T=/tmp/lab1007-$ARM; P=/tmp/arm1007$ARM; OUT=/tmp/lab1007-$ARM-sanity-$FS
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date "+%F %T") FSTYPE=$FS ARM=$ARM ($(cat /tmp/lab1007-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
if [ $FS = zfs ]; then
	:
	export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=2 TMP=/tmp/zfslab074
	rm -rf $TMP; mkdir -p $TMP
	M=/mnt/zfst
else
	export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
	M=/mnt/lfst
fi
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
B=/usr/lib64/lustre/tests
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do
	mount --bind $T/lustre/tests/.libs/$b $B/$b || echo "bind $b failed"
done
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs || echo "bind lfs failed"
for b in /usr/bin/lfs $B/llapi_scan_changelog_test; do
	echo "$b loads: $(LD_TRACE_LOADED_OBJECTS=1 $b | grep lustreapi | tr -s ' \t' ' ')"
done
cmp -s /usr/bin/lfs $T/lustre/utils/.libs/lfs && echo "bound lfs is NEW's"
ONLY="56Ea 56Eaa 56Eab 56Eb 56Ebb 56Ec 56Ed 56Eda 56Edb 56Ef 56Eg 56Eh 56Ei 56Ej 56Ek 56El 56Eea 160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
env ONLY="$ONLY" LFS=$T/lustre/utils/.libs/lfs bash $T/lustre/tests/sanity.sh > $OUT/sanity.txt 2>&1
echo "SANITY_RC=$?"
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do umount $B/$b; done
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/sanity.txt | cut -c1-160 > $OUT/verdicts.txt
echo "PASS $(grep -c '^PASS' $OUT/verdicts.txt)  FAIL $(grep -c 'FAIL' $OUT/verdicts.txt)  SKIP $(grep -c 'SKIP' $OUT/verdicts.txt)"
grep -E "FAIL|SKIP" $OUT/verdicts.txt
mount | grep -E '/usr/bin/lfs|lustre/tests/llapi' && echo "BIND LEFT"
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
[ $FS = zfs ] && rm -rf $TMP
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "SANITY RUN DONE"
