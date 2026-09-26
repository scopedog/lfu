#!/bin/bash
# 09-26: conf-sanity 300-305 at r0926b-tip, FSNAME=lfsc (formats its own).
set -u
H=/home/nishida; T=$H/lab0926-new; OUT=/tmp/lab0926-conf
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
env FSNAME=lfsc LUSTRE=/usr/lib64/lustre timeout 300 bash ./llmountcleanup.sh > $OUT/clean0.txt 2>&1
B=/usr/lib64/lustre/tests
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do mount --bind $T/lustre/tests/.libs/$b $B/$b; done
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 /usr/bin/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "scanner loads: $(LD_TRACE_LOADED_OBJECTS=1 $T/lustre/tests/.libs/llapi_scan_device_test | grep lustreapi | tr -s ' \t' ' ')"
env FSNAME=lfsc ONLY="300 301 302 303 304 305" LUSTRE=/usr/lib64/lustre \
    LFS=$T/lustre/utils/.libs/lfs SCANNER=$T/lustre/tests/.libs/llapi_scan_device_test \
    bash $T/lustre/tests/conf-sanity.sh > $OUT/cs.txt 2>&1
echo "CS_RC=$?"
V=$(grep -m1 -o 'version [^ ]*' $OUT/cs.txt); echo "framework saw: $V"
lsmod | grep -q '^lfu ' && echo "lfu.ko loaded by 305: $(modinfo -F version lfu)"
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do umount $B/$b; done
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/cs.txt | cut -c1-200
mount -t lustre | awk '{print "left mounted: "$3}'
echo "== end $(date '+%F %T')"
echo "CONF RUN DONE"
