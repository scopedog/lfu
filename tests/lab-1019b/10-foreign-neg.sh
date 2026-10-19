#!/bin/bash
# 10-19 lab B/#12 (root, clone VM): typed and untyped (! )--foreign on a walk,
# stock master (m = ee61b3f6dd) vs 69795 (mf: same liblustreapi_pfind.c as
# 08940f0ac9; only a sanity.sh skip message differs), ONE fixture, alternated.
set -u
OUT=/tmp/lab1019b-foreign; rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') m=$(cat /tmp/lab1018-m.sha) mf=$(cat /tmp/lab1018-mf.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q " $M " || { echo "ABORT: no mount"; exit 4; }
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"; [ -n "$V" ] || exit 3
echo "enable_foreign_dir: $(lctl get_param -n mdt.lfst-MDT0000.enable_foreign_dir 2>&1)"
echo "foreign_symlink_enable: $(lctl get_param -n llite.*.foreign_symlink_enable 2>&1)"
for a in m mf; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	echo "$a lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L/lfs | grep lustreapi | tr -s ' \t' ' ')  pfind.c md5 $(md5sum < /tmp/lab1018-$a/lustre/utils/liblustreapi_pfind.c | cut -c1-10)"
done
S=/tmp/lab1018-m/lustre/utils/.libs/lfs
D=$M/fn; U=$(cat /proc/sys/kernel/random/uuid)
$S mkdir -i 0 $D
touch $D/file; mkdir $D/dir
$S mkdir -c 2 $D/sdir || echo "striped dir FAILED"
$S setstripe --foreign=symlink --xattr=$U.fs --flags=0xda05 $D/ffile_sym || echo "ffile_sym FAILED"
$S setstripe --foreign=none --xattr=$U.fn --flags=0xda05 $D/ffile_none || echo "ffile_none FAILED"
$S mkdir --foreign=symlink --xattr=$U.ds --flags=0xda05 $D/fdir_sym || echo "fdir_sym FAILED"
$S mkdir --foreign=none --xattr=$U.dn --flags=0xda05 $D/fdir_none || echo "fdir_none FAILED"
echo "-- fixture:"
for o in dir sdir fdir_sym fdir_none; do echo "   $o: $($S getdirstripe $D/$o 2>&1 | head -4 | tr '\n' ' ' | cut -c1-160)"; done
for o in file ffile_sym ffile_none; do echo "   $o: $($S getstripe $D/$o 2>&1 | head -4 | tr '\n' ' ' | cut -c1-160)"; done
for i in 1 2; do
	for a in m mf; do
		L=/tmp/lab1018-$a/lustre/utils/.libs/lfs
		for q in "--foreign" "--foreign=symlink" "--foreign=none" "! --foreign" "! --foreign=symlink" "! --foreign=none"; do
			r=$($L find $D $q 2>&1 | sed "s|^$D|.|" | sort | xargs)
			echo "run$i $a: lfs find \$D $q  ->  [$r]"
		done
	done
done
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "FOREIGN-NEG DONE"
