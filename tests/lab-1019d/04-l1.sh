#!/bin/bash
# 10-19 lab d (root): L1 A/B.  A changelog user registered with -m creat,
# a scan asking for CL_UNLINK only: arm t's test11 binary, run with each
# arm's liblustreapi by LD_PRELOAD (the binary carries an RPATH).
set -u
OUT=/tmp/lab1019d-l1; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfsl MDSCOUNT=1 OSTCOUNT=1 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfsl
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client"; exit 4; }
MDT=lfsl-MDT0000
U=$(lctl --device $MDT changelog register -n -m creat)
echo "user $U: $(lctl get_param -n mdd.$MDT.changelog_users | grep "^$U")"
echo "mdd changelog_mask: $(lctl get_param -n mdd.$MDT.changelog_mask)"
lfs mkdir -i 0 $M/llapi_scan_changelog_test.d
BIN=/tmp/lab1019d-t/lustre/tests/.libs/llapi_scan_changelog_test
for n in o t; do
	L=/tmp/lab1019d-$n/lustre/utils/.libs/liblustreapi.so.1
	echo "--- lib $n ($(cat /tmp/lab1019d-$n.sha)): $(LD_PRELOAD=$L LD_TRACE_LOADED_OBJECTS=1 $BIN | grep lustreapi | tr -s ' \t' ' ')"
	LD_PRELOAD=$L $BIN -m $MDT -d $M -u $U -o 11
	echo "TEST11_RC_$n=$?"
done
lctl --device $MDT changelog deregister $U
echo "== end $(date '+%F %T')"
bash ./llmountcleanup.sh > $OUT/clean.txt 2>&1
echo "L1 DONE"
