#!/bin/bash
# 10-14 lab (as root on the clone VM): 68726 on the stack, arm n1014b.
# The equality stress on two trees -- createmany -m (no layouts) and one
# with 1000 striped files and a striped directory -- then an ASan build
# of the stress over the second.  Sanity (157c runs llapi_scan_test 0-17)
# is 02-sanity.sh n1014b, run separately.
set -u
ARM=n1014b; T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
O=/tmp/lab1014-batch; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
CF="-D_GNU_SOURCE -I$T/include -I$T/include/uapi -I$T/lustre/include"
gcc -O2 -o $O/stress /tmp/stress-batch.c $CF -L$P/lib -Wl,-rpath,$P/lib \
	-llustreapi -lpthread || { echo "cc stress failed"; exit 1; }
# no ASan here: the VM has no libasan runtime, so that runs on the host
cd /usr/lib64/lustre/tests; export PATH=/usr/lib64/lustre/tests:$PATH
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
mkdir $M/m && createmany -m $M/m/f 20000 > /dev/null
mkdir $M/s && lfs setstripe -c 2 $M/s && createmany -o $M/s/f 1000 > /dev/null
lfs setdirstripe -c 2 $M/s/striped && createmany -o $M/s/striped/g 20 > /dev/null
echo "trees: m $(find $M/m | wc -l), s $(find $M/s | wc -l)"
for d in m s; do
	echo "--- stress on $d"
	LD_PRELOAD=$P/lib/liblustreapi.so.1 $O/stress $M/$d; echo "rc=$?"
done
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo "BATCH RUN DONE"
