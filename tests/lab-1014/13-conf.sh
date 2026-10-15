#!/bin/bash
# 10-14 lab (root, clone VM): conf-sanity 300 after the split into
# 300a/300b/300c.  Usage: 13-conf.sh <arm> <conf-sanity.sh> <fstype> <tag>
# The arm's lfs, scanner and test binaries bound in, as lab-1006/05.
set -u
ARM=$1; CS=$2; FS=$3; TAG=$4
T=/tmp/lab1009-$ARM; OUT=/tmp/lab1014-conf-$TAG
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') $TAG arm=$ARM ($(cat /tmp/lab1009-$ARM.sha)) fs=$FS"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
E="FSNAME=lfsc LUSTRE=/usr/lib64/lustre FSTYPE=$FS"
[ $FS = zfs ] && E="$E TMP=/tmp/zfslab1014" && mkdir -p /tmp/zfslab1014
env $E timeout 300 bash ./llmountcleanup.sh > $OUT/clean0.txt 2>&1
B=/usr/lib64/lustre/tests
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do
	[ -e $T/lustre/tests/.libs/$b ] && mount --bind $T/lustre/tests/.libs/$b $B/$b
done
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs
cp $CS $T/lustre/tests/conf-sanity-$TAG.sh
env $E ONLY="300" LFS=$T/lustre/utils/.libs/lfs \
    SCANNER=$T/lustre/tests/.libs/llapi_scan_device_test \
    bash $T/lustre/tests/conf-sanity-$TAG.sh > $OUT/cs.txt 2>&1
echo "CS_RC=$?"
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do umount $B/$b 2>/dev/null; done
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/cs.txt | cut -c1-200
mount -t lustre | awk '{print "left mounted: "$3}'
env $E timeout 300 bash ./llmountcleanup.sh > $OUT/clean1.txt 2>&1
[ $FS = zfs ] && rm -rf /tmp/zfslab1014
echo "== end $(date '+%F %T')"
echo "CONF RUN DONE"
