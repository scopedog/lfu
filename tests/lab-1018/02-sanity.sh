#!/bin/bash
# 10-18 lab (root, clone VM): sanity subtests with one arm's lfs and
# liblustreapi, using another arm's sanity.sh.
# Usage: 02-sanity.sh <lib-arm> <script-arm> <tag> "<ONLY list>"
set -u
ARM=$1; SARM=$2; TAG=$3; ONLY=$4
T=/tmp/lab1018-$ARM; ST=/tmp/lab1018-$SARM; OUT=/tmp/lab1018-sanity-$TAG
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') lib=$ARM ($(cat /tmp/lab1018-$ARM.sha)) script=$SARM ONLY=$ONLY"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs || echo "bind lfs failed"
echo "lfs ld.so says: $(LD_TRACE_LOADED_OBJECTS=1 /usr/bin/lfs | grep lustreapi | tr -s ' \t' ' ')"
# the library a live lfs process has mapped
(sleep 3 | /usr/bin/lfs > /dev/null) & sleep 1
P=$(pgrep -nx lfs); echo "lfs pid $P maps: $(grep -o '/[^ ]*liblustreapi[^ ]*' /proc/$P/maps | sort -u | tr '\n' ' ')"
wait
echo "arm lib md5: $(md5sum < $T/lustre/utils/.libs/liblustreapi.so.1.0.0 | cut -c1-12)  'was empty when' in it: $(grep -c 'was empty when' $T/lustre/utils/.libs/liblustreapi.so.1.0.0)"
env ONLY="$ONLY" LFS=/usr/bin/lfs bash $ST/lustre/tests/sanity.sh > $OUT/sanity.txt 2>&1
echo "SANITY_RC=$?"
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/sanity.txt | cut -c1-200 > $OUT/verdicts.txt
echo "PASS $(grep -c '^PASS' $OUT/verdicts.txt)  FAIL $(grep -c 'FAIL' $OUT/verdicts.txt)  SKIP $(grep -c 'SKIP' $OUT/verdicts.txt)"
cat $OUT/verdicts.txt
mount | grep -E '/usr/bin/lfs' && echo "BIND LEFT"
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo "SANITY RUN DONE"
