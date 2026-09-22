#!/bin/bash
cd /home/nishida/projects/lustre/lustre-scanfid
T=$(mktemp -d)
printf '#include <lustre/lustreapi.h>\nint main(void){return 0;}\n' > $T/h.c
for c in $(git rev-list --reverse b7b1332a42a6959375c296f7a28564dcb90b2763..1a4e8b87b900c6e2b88709c1fc57edc1e30e5ebf); do
	git checkout -q -f --detach $c || { echo "$c CHECKOUT FAIL"; continue; }
	(cd lustre/utils && make -j8) > $T/b.log 2>&1
	b=$?
	gcc -fsyntax-only -Iinclude -Iinclude/uapi $T/h.c 2>$T/h.err; h=$?
	t=0
	for f in lustre/tests/llapi_scan_test.c lustre/tests/llapi_scan_device_test.c \
		 lustre/tests/llapi_scan_changelog_test.c; do
		[ -f $f ] || continue
		gcc -c -o /dev/null -Wall -Werror -D_GNU_SOURCE -Iinclude -Iinclude/uapi \
		    -Ilustre/utils -Ilustre/tests $f 2>>$T/t.err || t=1
	done
	echo "${c:0:10} build=$b hdr=$h tests=$t  $(git log -1 --format=%s $c | cut -c1-45)"
	[ $b -ne 0 ] && grep -m3 "error:" $T/b.log
	[ $h -ne 0 ] && head -3 $T/h.err
	[ $t -ne 0 ] && tail -3 $T/t.err
done
echo SWEEP-DONE
