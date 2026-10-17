#!/bin/bash
# 10-17 lab (root, clone VM): 68159 cc0ef9d2 A/B.  A namespace scan asking for
# LLAPI_SCAN_LMV_SHARD alone, old (o1) vs new (n1) liblustreapi, alternated,
# over a tree with a striped directory.  LD_PRELOAD: the VM binaries carry a
# DT_RPATH to ~/lfs68160-inst/lib.
set -u
OUT=/tmp/lab1017-ab; rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') o1=$(cat /tmp/lab1009-o1.sha) n1=$(cat /tmp/lab1009-n1.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
for a in o1 n1; do
	gcc -O2 -D_GNU_SOURCE -I/tmp/lab1009-$a/include -I/tmp/lab1009-$a/include/uapi \
	    -o /tmp/shardwant-$a /tmp/01-shardwant.c \
	    -L/tmp/lab1009-$a/lustre/utils/.libs -llustreapi || { echo "ABORT: cc $a"; exit 3; }
done
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfst; mount -t lustre | grep -q " $M " || { echo "ABORT: no mount"; exit 4; }
D=$M/ab; lfs mkdir -i 0 $D && lfs mkdir -c 2 $D/striped || echo "mkdir failed"
for d in a b c d; do mkdir -p $D/$d $D/striped/$d; done
for d in a b c d striped/a striped/b; do createmany -o $D/$d/f 500 > /dev/null; done
echo "objects: $(find $D | wc -l)"
for i in 1 2 3; do
	for a in o1 n1; do
		sync; echo 3 > /proc/sys/vm/drop_caches
		echo "$a run$i: $(LD_PRELOAD=/tmp/lab1009-$a/lustre/utils/.libs/liblustreapi.so.1 /tmp/shardwant-$a $D)"
	done
done
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "AB DONE"
