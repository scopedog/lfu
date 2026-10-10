#!/bin/bash
# 10-10 lab, stage 2 (as root): 68159 AI PS31.  Usage: 02-device.sh <arm>...
# (a) a plain ext4 image labelled "foo": the errno with and without --ost
#     old: --ost says ENOTSUP "OST: ... carries no target index", bare EINVAL
#     new: EINVAL both ways
# (b) the label probe: bytes read off an MDT image by a search with --mdt
#     old: the inode bitmap twice;  new: once.  Output must be identical.
set -u
exec > /tmp/lab1010-device.out 2>&1
IMG=/tmp/lab1010-plain.img
rm -f $IMG; truncate -s 64M $IMG; mkfs.ext4 -q -F -L foo $IMG
# the MDT image the stage-1 llmount left behind, unmounted; read only here
MDTIMG=/tmp/lustre-mdt1
echo "mdt image: label $(e2label $MDTIMG), $(dumpe2fs -h $MDTIMG 2>/dev/null | grep -i 'inode count')"
md5sum $MDTIMG > /tmp/lab1010-mdt.md5
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"
	$LFS find --device $IMG --ost 0 > /tmp/lab1010-dev-$ARM-a1.txt 2>&1; echo "$ARM plain --ost 0: rc=$? $(head -2 /tmp/lab1010-dev-$ARM-a1.txt | tr '\n' '|')"
	$LFS find --device $IMG --mdt 0 > /tmp/lab1010-dev-$ARM-a2.txt 2>&1; echo "$ARM plain --mdt 0: rc=$? $(head -2 /tmp/lab1010-dev-$ARM-a2.txt | tr '\n' '|')"
	$LFS find --device $IMG > /tmp/lab1010-dev-$ARM-a3.txt 2>&1; echo "$ARM plain bare:    rc=$? $(head -2 /tmp/lab1010-dev-$ARM-a3.txt | tr '\n' '|')"
	for opt in "--mdt 0" ""; do
		strace -f -e trace=pread64,read -o /tmp/lab1010-dev-$ARM.strace \
			$LFS find --device $MDTIMG $opt > /tmp/lab1010-dev-$ARM-b.txt 2>/tmp/lab1010-dev-$ARM-b.err
		rc=$?
		echo "$ARM mdt [$opt]: rc=$rc lines=$(wc -l < /tmp/lab1010-dev-$ARM-b.txt) md5=$(sort /tmp/lab1010-dev-$ARM-b.txt | md5sum | cut -c1-12) bytes_pread=$(awk -F'= ' '/pread64\(/ && $NF > 0 { s += $NF } END { print s + 0 }' /tmp/lab1010-dev-$ARM.strace)"
	done
	unset LD_PRELOAD
done
md5sum -c --quiet /tmp/lab1010-mdt.md5 && echo "mdt image untouched"
echo DEVICE DONE
