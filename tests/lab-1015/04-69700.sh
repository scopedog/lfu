#!/bin/bash
# 10-15 lab (root, clone VM): 69700 re-parented onto 68160 PS37 (m0 =
# 277b13d873).  Build it alone (below 68163: no ZFS backend), then all of
# llapi_scan_test (test19 is the rate limit) and conf-sanity 300 (device
# test7 is the rate limit on a target).
set -u
O=/tmp/lab1015-69700; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') m0 ($(cat /tmp/lab1009-m0.sha))"
sudo -u nishida bash /tmp/07-build-nozfs.sh m0 > $O/build.txt 2>&1
grep -q BUILD-OK $O/build.txt || { echo "ABORT: build"; tail -5 $O/build.txt; exit 3; }
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests; export PATH=/usr/lib64/lustre/tests:$PATH
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
TB=/tmp/lab1009-m0/lustre/tests/.libs/llapi_scan_test
mkdir -p $M/all; LD_PRELOAD=/tmp/arm1009m0/lib/liblustreapi.so.1 $TB -d $M/all -p /tmp > $O/all.txt 2>&1
echo "llapi_scan_test rc=$?"; grep -E "test19" $O/all.txt | cut -c1-150; tail -2 $O/all.txt
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
unset MDSCOUNT OSTCOUNT FSNAME
bash /tmp/lab1015-conf.sh m0 /tmp/lab1009-m0/lustre/tests/conf-sanity.sh ldiskfs 69700-m0 300
cat /tmp/lab1015-conf-69700-m0/run.txt
grep -E "test7 .*pace" /tmp/lab1015-conf-69700-m0/cs.txt | cut -c1-150
echo "== end $(date '+%F %T')"
echo "69700 RUN DONE"
