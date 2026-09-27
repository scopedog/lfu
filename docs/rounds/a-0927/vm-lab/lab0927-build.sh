#!/bin/bash
# 09-27: userspace arms for the r0927-tip VM test. new = r0927-tip,
# old = backup/artem-0924-pre-0927 (r0926b-tip). Private prefixes only.
set -u
for n in "$@"; do
	T=$HOME/lab0927-$n; P=$HOME/arm0927$n
	rm -rf $T $P; tar -C $HOME -xzf /tmp/lab0927-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules --disable-server --disable-iokit) > $HOME/lab0927-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -j4) > $HOME/lab0927-$n-make.log 2>&1 || { echo "make $n failed"; grep -m5 " error: " $HOME/lab0927-$n-make.log; exit 1; }
	gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so $T/lustre/utils/libscan_ldiskfs.c -include $T/config.h -I $T/include -I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 -lext2fs || { echo "plugin $n failed"; exit 1; }
	# conf-sanity 305's kernel backend (lfu.ko's /dev/lfu_scan): the 09-26 lesson
	gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_kernel.so $T/lustre/utils/libscan_kernel.c -include $T/config.h -I $T/include -I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 || { echo "kernel plugin $n failed"; exit 1; }
	mkdir -p $P/lib/lustre
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	cp $T/lustre/utils/scan_osd_ldiskfs.so $T/lustre/utils/scan_osd_kernel.so $P/lib/lustre/
	grep -c " error: " $HOME/lab0927-$n-make.log | sed "s/^/  make errors: /"
	grep -m1 -E "define HAVE_STATX\b" $T/config.h || echo "  HAVE_STATX not defined"
	echo "== $n: PLUGIN_DIR strings: $(strings $T/lustre/utils/.libs/liblustreapi.so.1 | grep -m2 "$P")"
	ls -la --time-style=+%T $T/lustre/utils/.libs/lfs $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $T/lustre/tests/.libs/llapi_scan_test $T/lustre/tests/.libs/llapi_scan_changelog_test $T/lustre/tests/.libs/llapi_scan_device_test $P/lib/lustre/scan_osd_ldiskfs.so $P/lib/lustre/scan_osd_kernel.so 2>&1 | awk '{print $6, $NF}'
	readelf -d $T/lustre/utils/.libs/lfs | grep -i path
	ldd $P/lib/lustre/scan_osd_ldiskfs.so | grep ext2fs
done
echo BUILD-OK
