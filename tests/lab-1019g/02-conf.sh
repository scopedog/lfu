#!/bin/bash
# 10-20 lab g (root, clone VM): conf-sanity with one arm's lfs, library,
# plugin and scan tool, and another arm's conf-sanity.sh.  FSNAME=lfsc.
# Usage: 02-conf.sh <lib-arm> <script-arm> <tag> "<ONLY>"
set -u
ARM=$1; SARM=$2; TAG=$3; ONLY=$4
T=/tmp/lab1019g-$ARM; ST=/tmp/lab1019g-$SARM; OUT=/tmp/lab1019g-conf-$TAG
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') lib=$ARM ($(cat /tmp/lab1019g-$ARM.sha)) script=$SARM ONLY=$ONLY"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
env FSNAME=lfsc LUSTRE=/usr/lib64/lustre timeout 300 bash ./llmountcleanup.sh > $OUT/clean0.txt 2>&1
L=$T/lustre/utils/.libs/lfs
S=$T/lustre/tests/.libs/llapi_scan_device_test
[ -x $S ] || S=/bin/false
mount --bind $L /usr/bin/lfs
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L | grep lustreapi | tr -s ' \t' ' ')"
echo "lib md5: $(md5sum < /tmp/arm1019g$ARM/lib/liblustreapi.so.1.0.0 | cut -c1-12)  plugin: $(ls /tmp/arm1019g$ARM/lib/lustre/)"
env FSNAME=lfsc ONLY="$ONLY" LUSTRE=/usr/lib64/lustre LFS=$L SCANNER=$S \
    bash $ST/lustre/tests/conf-sanity.sh > $OUT/cs.txt 2>&1
echo "CS_RC=$?"
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:|error:" $OUT/cs.txt | cut -c1-240
grep -E "scanned .* objects|found all|objects not given back|%LO" $OUT/cs.txt | cut -c1-240 | head -20
env FSNAME=lfsc LUSTRE=/usr/lib64/lustre timeout 300 bash ./llmountcleanup.sh > $OUT/clean1.txt 2>&1
mount -t lustre | awk '{print "left mounted: "$3}'
echo "== end $(date '+%F %T')"
echo "CONF RUN DONE"
