#!/bin/bash
# Build every commit of the stack in ~/lfs-artem-0924: utils, the public
# header, the scan test programs, and both scan backends (-O2 -Werror).
# Usage: sweep.sh BASE TIP
set -u
cd /home/nishida/lfs-artem-0924 || exit 1
B=$1; TIP=$2; br=$(git branch --show-current)
T=$(mktemp -d); n=$(git rev-list --count $B..$TIP)
echo "SWEEP $(git rev-parse --short $B)..$(git rev-parse --short $TIP), $n commits"
printf '#include <lustre/lustreapi.h>\nint main(void){return 0;}\n' > $T/h.c
CF="-O2 -Wall -Werror -include config.h -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 -I include -I include/uapi -I lustre/utils"
ok=0
for c in $(git rev-list --reverse $B..$TIP); do
	git checkout -q --detach $c || { echo "$c CHECKOUT FAIL"; continue; }
	make -C lustre/utils -j8 > $T/b.log 2>&1; b=$?
	gcc -fsyntax-only -Iinclude -Iinclude/uapi $T/h.c 2>$T/h.err; h=$?
	t=0; : > $T/t.err
	for f in lustre/tests/llapi_scan_test.c lustre/tests/llapi_scan_device_test.c \
		 lustre/tests/llapi_scan_changelog_test.c; do
		[ -f $f ] || continue
		gcc -c -o /dev/null -O2 -Wall -Werror -D_GNU_SOURCE -Iinclude -Iinclude/uapi \
		    -Ilustre/utils -Ilustre/tests $f 2>>$T/t.err || t=1
	done
	l=-; [ -f lustre/utils/libscan_ldiskfs.c ] && { gcc -c -o /dev/null $CF lustre/utils/libscan_ldiskfs.c 2>$T/l.err; l=$?; }
	z=-; [ -f lustre/utils/libscan_zfs.c ] && { gcc -c -o /dev/null $CF -I/usr/include/libspl -I/usr/include/libzfs lustre/utils/libscan_zfs.c 2>$T/z.err; z=$?; }
	echo "$(git rev-parse --short $c) build=$b hdr=$h tests=$t ldiskfs=$l zfs=$z  $(git log -1 --format=%s $c | cut -c1-45)"
	[ "$b$h$t$l$z" = "00000" -o "$b$h$t" = "000" -a "$l" != 1 -a "$z" != 1 ] && ok=$((ok+1))
	[ $b -ne 0 ] && grep -m3 "error" $T/b.log
	[ $t -ne 0 ] && head -3 $T/t.err
	[ "$l" = 1 ] && head -3 $T/l.err
	[ "$z" = 1 ] && head -3 $T/z.err
done
git checkout -q $br
echo "SWEEP-DONE $ok/$n clean, tip $(git rev-parse --short $TIP)"
