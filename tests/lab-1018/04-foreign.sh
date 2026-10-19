#!/bin/bash
# 10-18 lab (root, clone VM): #15, lfs find --foreign on a namespace walk,
# stock master (m) vs master + fix (mf), alternated on ONE fixture.
set -u
OUT=/tmp/lab1018-foreign; rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') m=$(cat /tmp/lab1018-m.sha) mf=$(cat /tmp/lab1018-mf.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q " $M " || { echo "ABORT: no mount"; exit 4; }
echo "enable_foreign_dir: $(lctl get_param -n mdt.lfst-MDT0000.enable_foreign_dir 2>&1)"
for a in m mf; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	echo "$a lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L/lfs | grep lustreapi | tr -s ' \t' ' ')"
done
S=/tmp/lab1018-m/lustre/utils/.libs/lfs
D=$M/fr; U=$(cat /proc/sys/kernel/random/uuid)
$S mkdir -i 0 $D
$S mkdir --foreign=none --xattr=$U --flags=0xda05 $D/fdir || echo "foreign dir FAILED"
$S setstripe --foreign=none --xattr=$U --flags=0xda05 $D/ffile || echo "foreign file FAILED"
$S mkdir -c 2 $D/sdir || echo "striped dir FAILED"
mkdir $D/dir; touch $D/file $D/sdir/f
echo "-- fixture:"
for o in fdir sdir dir; do echo "   $o: $($S getdirstripe $D/$o 2>&1 | head -3 | tr '\n' ' ' | cut -c1-150)"; done
echo "   ffile: $($S getstripe $D/ffile 2>&1 | head -3 | tr '\n' ' ' | cut -c1-150)"
for i in 1 2; do
	for a in m mf; do
		L=/tmp/lab1018-$a/lustre/utils/.libs/lfs
		for q in "--foreign" "! --foreign" "--foreign -type d" "! --foreign -type d" "--foreign=none -type d" "--foreign=symlink"; do
			r=$($L find $D $q 2>&1 | sed "s|^$D|.|" | sort | xargs)
			echo "run$i $a: lfs find \$D $q  ->  [$r]"
		done
	done
done
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "FOREIGN DONE"
