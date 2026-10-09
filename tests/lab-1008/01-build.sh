#!/bin/bash
# 10-07 lab, stage 1 (as nishida on the clone VM): build the arms.
#   old = 036735e9fb (10-06 tip), new = a1008-tip (the 10-07 AI round).
# Same recipe as lab-1006/11-build.sh.  Trees
# /tmp/lab1008-<arm>, prefixes /tmp/arm1008<arm>; source from git archive.
set -u
for n in "$@"; do
	T=/tmp/lab1008-$n; P=/tmp/arm1008$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1008-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1008-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1008-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs libscan_zfs.la &&
	 make -C lustre/tests llapi_scan_changelog_test llapi_scan_test \
		llapi_scan_device_test) > /tmp/lab1008-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1008-$n-make2.log; exit 1; }
	echo "  $n ($(cat /tmp/lab1008-$n.sha)) make -k errors in: $(grep ' error: ' /tmp/lab1008-$n-make.log | sed 's/:.*//' | sort -u | tr '\n' ' ')"
	gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so \
		$T/lustre/utils/libscan_ldiskfs.c -include $T/config.h -I $T/include \
		-I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE \
		-D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 \
		-lext2fs || { echo "ldiskfs plugin $n failed"; exit 1; }
	mkdir -p $P/lib/lustre
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	cp $T/lustre/utils/scan_osd_ldiskfs.so $P/lib/lustre/
	cp $T/lustre/utils/scan_osd_zfs.so $P/lib/lustre/scan_osd_zfs.so
	echo "  $n zfs probe: $(grep -m1 'zfs libzpool headers usable' /tmp/lab1008-$n-conf.log | cut -c1-220)"
	echo "  $n PLUGIN_DIR: $(strings $P/lib/liblustreapi.so.1 | grep -m1 "$P/lib/lustre")"
	readelf -d $T/lustre/utils/.libs/lfs | grep -i path
done
echo BUILD-OK
