#!/bin/bash
# 10-19 lab (nishida, clone VM): build both arms, userspace only, plus the
# race harness against each arm and the open() shim.  Recipe of lab-1018.
set -u
for n in "$@"; do
	T=/tmp/lab1019-$n; P=/tmp/arm1019$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1019-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1019-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1019-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs &&
	 make -C lustre/tests llapi_scan_changelog_test llapi_scan_test) > /tmp/lab1019-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1019-$n-make2.log; exit 1; }
	mkdir -p $P/lib
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	gcc -O2 -Wall -D_GNU_SOURCE -o /tmp/scanfid_race-$n /tmp/scanfid_race.c \
		-I$T/include -I$T/include/uapi -I$T/lustre/include \
		-L$P/lib -llustreapi -Wl,--disable-new-dtags,-rpath,$P/lib -ldl ||
		{ echo "harness $n failed"; exit 1; }
	echo "  $n ($(cat /tmp/lab1019-$n.sha)) fd2fid check in lib: $(grep -c 'the gather opens a regular file again' $T/lustre/utils/liblustreapi_scan.c)"
	ls -l --time-style=+%T $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $T/lustre/utils/.libs/lfs /tmp/scanfid_race-$n
	md5sum $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $P/lib/liblustreapi.so.1.0.0 | cut -c1-12
done
gcc -shared -fPIC -Wall -o /tmp/race_open.so /tmp/race_open.c -ldl || exit 1
echo BUILD-OK
