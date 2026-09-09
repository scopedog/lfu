#!/bin/bash
# Build lustre/utils at every commit of the stack, and syntax-check the test
# programs, so "does not compile at commit N" cannot survive again.
cd /home/nishida/projects/lustre/lustre-scanfid
T=$(mktemp -d)
printf '#include <lustre/lustreapi.h>\nint main(void){return 0;}\n' > $T/h.c
for c in $(git log --format=%h -20 | tac); do
	git checkout -q --detach $c || { echo "$c CHECKOUT FAIL"; continue; }
	(cd lustre/utils && make -j8) > $T/b.log 2>&1
	b=$?
	gcc -fsyntax-only -Iinclude -Iinclude/uapi $T/h.c 2>$T/h.err; h=$?
	t=0
	for f in lustre/tests/llapi_scan_test.c lustre/tests/llapi_scan_device_test.c \
		 lustre/tests/llapi_scan_changelog_test.c; do
		[ -f $f ] || continue
		gcc -fsyntax-only -D_GNU_SOURCE -Iinclude -Iinclude/uapi \
		    -Ilustre/utils -Ilustre/tests $f 2>>$T/t.err || t=1
	done
	echo "$c build=$b hdr=$h tests=$t  $(git log -1 --format=%s $c | cut -c1-45)"
	[ $b -ne 0 ] && grep -m3 "error:" $T/b.log
	[ $t -ne 0 ] && tail -3 $T/t.err
done
git checkout -q lab/spgot
echo SWEEP-DONE
