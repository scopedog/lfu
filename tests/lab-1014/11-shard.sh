#!/bin/bash
# 10-14 lab (root, clone VM): the shard skip moved into 68159'.  Run on
# 68160' arms, where lfs find --device arrives: t0 = before the move, t1 =
# after.  (A first run on 68159' arms s0/s1 tested nothing: no --device.)
# A directory striped over two MDTs holds 10 subdirectories; the filesystem
# is unmounted and each MDT image searched with -type d.  A walk sees 11
# directories (sd and its 10).  Summed over both MDTs, t0 should add a shard
# per MDT and t1 should not.
set -u
O=/tmp/lab1014-shard; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests; export PATH=/usr/lib64/lustre/tests:$PATH
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=1
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
lfs mkdir -c 2 $M/sd && for i in $(seq 1 10); do mkdir $M/sd/d$i; done
echo "walk: $(lfs find $M/sd -type d | wc -l) directories under sd (sd included)"
lfs getdirstripe $M/sd | head -3
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1
ls -la /tmp/lfst-mdt* 2>&1 | head -3
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	# /tmp/lustre-mdt* is an older fixture, not this filesystem
	for img in /tmp/lfst-mdt1 /tmp/lfst-mdt2; do
		[ -e $img ] || { echo "ABORT: no $img"; continue; }
		out=$(LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device $img -type d 2>$O/err-$ARM)
		echo "$ARM $(basename $img): $(echo -n "$out" | grep -c .) directories; $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
		grep -v "^$" $O/err-$ARM | head -3
	done
done
echo "== end $(date '+%F %T')"
echo SHARD DONE
