#!/bin/bash
# 10-15 IGIF-root A/B (as root): i0 = 68288 PS30 (fac02ee959), i1 = fix.
# Expect: std image, i0 == i1; igif image, i1 == std, i0 names nothing.
set -u
exec > /tmp/lab1015-ab.out 2>&1
for IMG in std igif; do md5sum /tmp/lab1015-mdt-$IMG.img; done > /tmp/lab1015-img.md5
for ARM in i0 i1; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"
	for IMG in std igif; do
		O=/tmp/lab1015-$ARM-$IMG
		$LFS find --device /tmp/lab1015-mdt-$IMG.img --paths > $O.txt 2> $O.err
		echo "$ARM $IMG: rc=$? lines=$(wc -l < $O.txt) md5=$(sort $O.txt | md5sum | cut -c1-12) err=$(tr '\n' '|' < $O.err | cut -c1-160)"
	done
	unset LD_PRELOAD
done
md5sum -c --quiet /tmp/lab1015-img.md5 && echo "images untouched"
for f in i0-std i1-std i1-igif i0-igif; do echo "--- $f"; sort /tmp/lab1015-$f.txt; done
cmp -s <(sort /tmp/lab1015-i0-std.txt) <(sort /tmp/lab1015-i1-std.txt) && echo "std: i0 == i1"
cmp -s <(sort /tmp/lab1015-i0-std.txt) <(sort /tmp/lab1015-i1-igif.txt) && echo "i1 igif == std"
echo AB DONE
