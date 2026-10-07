#!/bin/bash
# Build lustre/utils at every commit of BASE..TIP in a configured tree, and
# compile the test programs.  Usage: build-sweep-range.sh TREE BASE TIP
TREE=$1 BASE=$2 TIP=$3
cd "$TREE" || exit 1
T=$(mktemp -d)
printf '#include <lustre/lustreapi.h>\nint main(void){return 0;}\n' > $T/h.c
n=$(git rev-list --count $BASE..$TIP)
echo "SWEEP $(git rev-parse --short $BASE)..$(git rev-parse --short $TIP), $n commits in $TREE"
for c in $(git rev-list --reverse $BASE..$TIP); do
	git checkout -q --detach $c || { echo "$c CHECKOUT FAIL"; continue; }
	(cd lustre/utils && make -j8) > $T/b.log 2>&1
	b=$?
	gcc -fsyntax-only -Iinclude -Iinclude/uapi $T/h.c 2>$T/h.err; h=$?
	t=0; : > $T/t.err
	for f in lustre/tests/llapi_scan_test.c lustre/tests/llapi_scan_device_test.c \
		 lustre/tests/llapi_scan_changelog_test.c; do
		[ -f $f ] || continue
		gcc -c -O2 -o /dev/null -Wall -Werror -D_GNU_SOURCE -Iinclude \
		    -Iinclude/uapi -Ilustre/utils -Ilustre/tests $f 2>>$T/t.err || t=1
	done
	s=0; bash -n lustre/tests/sanity.sh || s=1
	echo "$(git rev-parse --short $c) build=$b hdr=$h tests=$t sh=$s  $(git log -1 --format=%s $c | cut -c1-45)"
	[ $b -ne 0 ] && grep -m3 "error:" $T/b.log
	[ $t -ne 0 ] && tail -3 $T/t.err
done
echo SWEEP-DONE
