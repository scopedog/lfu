#!/bin/bash
# 10-10 lab, stage 6 (as root): 68418 AI PS17, --changelog --resolve tests a
# recorded name before the lookup.  Usage: 06-clresolve.sh <arm>...
#   gone a.txt, -name '*.o' -size +0: old counts it "could not be decided",
#   new does not.  The printed set must be the same on both arms, and
#   llapi_scan_fid lookups (fid2path ioctls, by strace) drop on new.
set -u
exec > /tmp/lab1010-clresolve.out 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1010-llmount6.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
KEEP=$(lctl --device $MDT changelog_register -n)
mkdir $M/d; for i in 1 2 3; do echo x > $M/d/k$i.o; echo x > $M/d/t$i.txt; done
touch $M/d/gone.txt $M/d/gone.o; mkdir $M/d/sub.o
sync; sleep 1; rm $M/d/gone.txt $M/d/gone.o; sync; sleep 1
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha))"
	n=0
	for args in "-name *.o -size +0" "-name *.o" "-name *.o -type f" "-type d" "! -name *.o -type f" ""; do
		n=$((n + 1))
		set -f
		strace -f -e trace=ioctl -o /tmp/lab1010-clr-$ARM.strace $LFS find $M --changelog all --resolve $args \
			> /tmp/lab1010-clr-$ARM-$n.txt 2> /tmp/lab1010-clr-$ARM-$n.err
		rc=$?
		set +f
		echo "$ARM [$args]: rc=$rc lines=$(wc -l < /tmp/lab1010-clr-$ARM-$n.txt) md5=$(sort /tmp/lab1010-clr-$ARM-$n.txt | md5sum | cut -c1-10) ioctls=$(wc -l < /tmp/lab1010-clr-$ARM.strace) | $(tr '\n' '|' < /tmp/lab1010-clr-$ARM-$n.err)"
	done
	unset LD_PRELOAD
done
lctl --device $MDT changelog_deregister $KEEP > /dev/null
bash ./llmountcleanup.sh > /tmp/lab1010-cleanup6.txt 2>&1; echo "cleanup rc=$?"
echo CLRESOLVE DONE
