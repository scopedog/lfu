#!/bin/bash
# 10-20 lab h (root, clone VM): sanity subtests with one arm's lfs, liblustreapi
# and llapi_scan*_test binaries, and that arm's sanity.sh.
# Usage: 02-sanity.sh <arm> <tag> <mdscount> "<ONLY list>"
set -u
ARM=$1; TAG=$2; NMDS=$3; ONLY=$4
T=/tmp/lab1019h-$ARM; OUT=/tmp/lab1019h-sanity-$TAG
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') arm=$ARM ($(cat /tmp/lab1019h-$ARM.sha)) ONLY=$ONLY MDSCOUNT=$NMDS"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=$NMDS OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
B="/usr/bin/lfs"
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs || echo "bind lfs failed"
for t in llapi_scan_test llapi_scan_changelog_test; do
	src=$T/lustre/tests/.libs/$t; [ -f $src ] || src=$T/lustre/tests/$t
	dst=$(command -v $t || echo /usr/lib64/lustre/tests/$t)
	[ -e $dst ] || { echo "no installed $t to bind over"; continue; }
	mount --bind $src $dst && B="$B $dst" && echo "bound $src over $dst"
	echo "  $t ld.so: $(LD_TRACE_LOADED_OBJECTS=1 $dst | grep lustreapi | tr -s ' \t' ' ')"
done
echo "lfs ld.so: $(LD_TRACE_LOADED_OBJECTS=1 /usr/bin/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "arm lib md5: $(md5sum < $T/lustre/utils/.libs/liblustreapi.so.1.0.0 | cut -c1-12)"
env ONLY="$ONLY" LFS=/usr/bin/lfs bash $T/lustre/tests/sanity.sh > $OUT/sanity.txt 2>&1
echo "SANITY_RC=$?"
for b in $B; do umount $b; done
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/sanity.txt | cut -c1-200 > $OUT/verdicts.txt
echo "PASS $(grep -c '^PASS' $OUT/verdicts.txt)  FAIL $(grep -c 'FAIL' $OUT/verdicts.txt)  SKIP $(grep -c 'SKIP' $OUT/verdicts.txt)"
cat $OUT/verdicts.txt
mount | grep -E 'lfs |_test ' && echo "BIND LEFT"
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
