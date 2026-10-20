#!/bin/bash
# 10-20 lab h (nishida, clone VM): build the arms, userspace only, with a
# private PLUGIN_DIR (the prefix) holding the arm's hand-built ldiskfs
# backend.  Recipe of lab-1019c/01-build.sh.
set -u
for n in "$@"; do
	T=/tmp/lab1019h-$n; P=/tmp/arm1019h$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1019h-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1019h-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1019h-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs &&
	 make -C lustre/tests llapi_scan_changelog_test llapi_scan_test llapi_scan_device_test) > /tmp/lab1019h-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1019h-$n-make2.log; exit 1; }
	gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so \
		$T/lustre/utils/libscan_ldiskfs.c -include $T/config.h -I $T/include \
		-I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE \
		-D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 \
		-lext2fs || { echo "ldiskfs plugin $n failed"; exit 1; }
	mkdir -p $P/lib/lustre
	cp $T/lustre/utils/scan_osd_ldiskfs.so $P/lib/lustre/
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	echo "  $n ($(cat /tmp/lab1019h-$n.sha)) PLUGIN_DIR in lib: $(strings $P/lib/liblustreapi.so.1 | grep -m1 "^$P/lib/lustre")"
	ls -l --time-style=+%T $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $T/lustre/utils/.libs/lfs $T/lustre/tests/.libs/llapi_scan_changelog_test
	md5sum $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $P/lib/liblustreapi.so.1.0.0 | cut -c1-12
done
echo BUILD-OK
