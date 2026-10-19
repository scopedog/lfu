#!/bin/bash
# 10-19 lab b (nishida, clone VM): build the arms, userspace only.
# Recipe of lab-1019/01-build.sh.  Arm x: the cookie rewrite stores the
# reached index by position in mdts[] rather than by MDT number, so a run
# over MDT0001 alone writes its index to MDT0000's line.
set -u
for n in "$@"; do
	T=/tmp/lab1019b-$n; P=/tmp/arm1019b$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1019b-$n.tgz || exit 1
	if [ $n = x ]; then
		F=$T/lustre/utils/liblustreapi_pfind.c
		[ $(grep -c '^			starts\[mdts\[i\]\] = reached\[i\];$' $F) = 1 ] || { echo "break anchor not unique"; exit 1; }
		sed -i 's/^\t\t\tstarts\[mdts\[i\]\] = reached\[i\];$/\t\t\tstarts[i] = reached[i];/' $F
		echo "  x broken line: $(grep -n '^			starts\[i\] = reached\[i\];$' $F)"
	fi
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1019b-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1019b-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs &&
	 make -C lustre/tests llapi_scan_changelog_test llapi_scan_test) > /tmp/lab1019b-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1019b-$n-make2.log; exit 1; }
	mkdir -p $P/lib
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	echo "  $n ($(cat /tmp/lab1019b-$n.sha)) DNE block in sanity.sh: $(grep -c 'the MDT0001 run moved MDT0000' $T/lustre/tests/sanity.sh)"
	ls -l --time-style=+%T $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $T/lustre/utils/.libs/lfs
	md5sum $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $P/lib/liblustreapi.so.1.0.0 | cut -c1-12
	readelf -d $T/lustre/utils/.libs/lfs | grep -i path
done
echo BUILD-OK
