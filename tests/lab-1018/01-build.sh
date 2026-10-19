#!/bin/bash
# 10-18 lab (as nishida on the clone VM): build the arms.
#   o = b1018-fork-1014 f9034db8d7 (before #21), n = fork-1014 d9cc93e608,
#   m = master-1014 ee61b3f6dd (stock), mf = m + the #15 foreign fix.
# Recipe of lab-1014/07-build-nozfs.sh; trees /tmp/lab1018-<arm>,
# prefixes /tmp/arm1018<arm>; source from git archive.
set -u
for n in "$@"; do
	T=/tmp/lab1018-$n; P=/tmp/arm1018$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1018-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1018-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1018-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs &&
	 make -C lustre/tests $(for t in llapi_scan_changelog_test llapi_scan_test llapi_scan_device_test; do [ -f $T/lustre/tests/$t.c ] && echo $t; done)) > /tmp/lab1018-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1018-$n-make2.log; exit 1; }
	echo "  $n ($(cat /tmp/lab1018-$n.sha)) make -k errors in: $(grep ' error: ' /tmp/lab1018-$n-make.log | sed 's/:.*//' | sort -u | tr '\n' ' ')"
	if [ -f $T/lustre/utils/libscan_ldiskfs.c ]; then
		gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so \
			$T/lustre/utils/libscan_ldiskfs.c -include $T/config.h -I $T/include \
			-I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE \
			-D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 \
			-lext2fs || { echo "ldiskfs plugin $n failed"; exit 1; }
		mkdir -p $P/lib/lustre
		cp $T/lustre/utils/scan_osd_ldiskfs.so $P/lib/lustre/
	fi
	mkdir -p $P/lib
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	ls -l --time-style=+%T $T/lustre/utils/.libs/liblustreapi.so.1.0.0 $T/lustre/utils/.libs/lfs
	readelf -d $T/lustre/utils/.libs/lfs | grep -i path
done
echo BUILD-OK
