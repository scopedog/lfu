#!/bin/bash
# Lift-and-compare for 68419 S4: old 0f9b013492 vs new 88ee77c068.
set -e
H=$(cd $(dirname $0) && pwd)
W=${W:-$(mktemp -d)}
T=~/lfs-fork-1014
for arm in old:0f9b013492 new:88ee77c068; do
	n=${arm%%:*} c=${arm#*:}
	mkdir -p $W/$n
	git -C $T show $c:lustre/utils/liblustreapi_pfind.c > $W/$n/src.c
	python3 $H/lift.py $W/$n/src.c $W/$n/lifted.c
	gcc -Wall -include stdarg.h -I$W/$n -o $W/$n/h $H/harness.c
	: > $W/$n/cookie
	echo "===== $n ($c)"
	$W/$n/h $W/$n/cookie
done
