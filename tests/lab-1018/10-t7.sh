#!/bin/bash
# 10-18 pass f lab (root, clone VM): #1, objects skipped as SKIP_INVALID
# before the pre-filter now take a rate slot.  Fixture: an MDT image with
# 3000 files, unmounted and copied; 2000 of the files' inodes get an invalid
# file type with debugfs (checksum rewritten, so the read succeeds and only
# scan_inode_plausible() refuses it).  test7 (paced >= 95% of seen/rate) and
# test0 (accounting) on the clean copy and the torn copy, arms r0 (old 69700
# 4d35b0b1b0) and r1 (fixed dfa074ae7d), alternated twice.
set -u
OUT=/tmp/lab1018-t7; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=1 LUSTRE=/usr/lib64/lustre
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
mkdir -p /mnt/lfst/t && /usr/lib64/lustre/tests/createmany -m /mnt/lfst/t/f 3000 | tail -1
sync
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
mount | grep -q ' type lustre' && { echo "ABORT: still mounted"; exit 3; }
cp --sparse=always /tmp/lfst-mdt1 $OUT/clean.img
cp --sparse=always /tmp/lfst-mdt1 $OUT/torn.img
debugfs -R 'ls -l /ROOT/t' $OUT/torn.img 2>/dev/null | awk '$NF ~ /^f[0-9]+$/ {print $1}' | head -2000 > $OUT/inos
echo "inodes to tear: $(wc -l < $OUT/inos), first $(head -1 $OUT/inos) last $(tail -1 $OUT/inos)"
sed 's/.*/sif <&> mode 0170644/' $OUT/inos > $OUT/cmds
debugfs -w -f $OUT/cmds $OUT/torn.img > $OUT/debugfs.txt 2>&1; echo "debugfs rc=$? errors: $(grep -ci 'error\|invalid' $OUT/debugfs.txt)"
i=$(head -1 $OUT/inos); echo "torn sample: $(debugfs -R "stat <$i>" $OUT/torn.img 2>/dev/null | grep -m1 -o 'Mode: *[0-9]*')"
e2fsck -fn $OUT/torn.img > $OUT/fsck.txt 2>&1; echo "e2fsck -fn rc=$? (expected non-zero on torn)"
for a in r0 r1; do
	B=/tmp/lab1018-$a/lustre/tests/llapi_scan_device_test
	echo "$a test bin: $(file -b $B | cut -c1-40); lib: $(LD_LIBRARY_PATH=/tmp/arm1018$a/lib LD_TRACE_LOADED_OBJECTS=1 $B 2>&1 | grep -o '/[^ ]*liblustreapi[^ ]*')"
	echo "$a lib md5 $(md5sum < /tmp/arm1018$a/lib/liblustreapi.so.1.0.0 | cut -c1-10)"
done
for pass in 1 2; do
for a in r0 r1; do
for img in clean torn; do
	B=/tmp/lab1018-$a/lustre/tests/llapi_scan_device_test
	echo "--- pass $pass arm $a $img"
	LD_LIBRARY_PATH=/tmp/arm1018$a/lib strace -f -e trace=openat -o $OUT/st.$a.$img.$pass \
		$B -d $OUT/$img.img -o 0,7 2>&1 | tail -6
	echo "rc=${PIPESTATUS[0]}  plugin opened: $(grep -o '/[^"]*scan_osd[^"]*' $OUT/st.$a.$img.$pass | sort -u | tr '\n' ' ')"
done; done; done
echo "== end $(date '+%F %T')"
echo T7 DONE
