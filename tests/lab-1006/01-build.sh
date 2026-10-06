#!/bin/bash
# 10-06 lab, stage 1 (as nishida on the clone VM): build both arms.
# old = a1005-pushed 3a179e7307, new = fix-1006 8506d66293.
# Trees /tmp/lab1006-<arm>, prefixes /tmp/arm1006<arm> (/home is 92% full).
# ZFS-capable userspace configure; make -k (libmount_utils_zfs.c needs the
# server definitions, upstream), then the targets the lab uses, asserted.
# scan_osd_zfs.so is built twice: as committed (.orig), and a Z1 variant
# whose spa_config_path comes from $LFU_ZTEST_CACHE, standing in for ZFS
# 2.4's /boot/zfs/zpool.cache fallback that 2.2.11 lacks.
set -u
for n in "$@"; do
	T=/tmp/lab1006-$n; P=/tmp/arm1006$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab1006-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules \
		--disable-iokit --with-zfs=/usr/src/zfs-2.2.11) \
		> /tmp/lab1006-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	(cd $T && make -k -j4) > /tmp/lab1006-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs libscan_zfs.la &&
	 make -C lustre/tests llapi_scan_changelog_test llapi_scan_test \
		llapi_scan_device_test) > /tmp/lab1006-$n-make2.log 2>&1 ||
		{ echo "make targets $n failed"; grep -m5 " error: " /tmp/lab1006-$n-make2.log; exit 1; }
	echo "  $n make -k errors in: $(grep ' error: ' /tmp/lab1006-$n-make.log | sed 's/:.*//' | sort -u | tr '\n' ' ')"
	gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so \
		$T/lustre/utils/libscan_ldiskfs.c -include $T/config.h -I $T/include \
		-I $T/include/uapi -I $T/lustre/utils -D_GNU_SOURCE \
		-D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 \
		-lext2fs || { echo "ldiskfs plugin $n failed"; exit 1; }
	mkdir -p $P/lib/lustre
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	cp $T/lustre/utils/scan_osd_ldiskfs.so $P/lib/lustre/
	cp $T/lustre/utils/scan_osd_zfs.so $P/lib/lustre/scan_osd_zfs.so.orig
	# the Z1 variant
	F=$T/lustre/utils/libscan_zfs.c
	grep -c 'spa_config_path = (char \*)"";' $F | grep -qx 1 || { echo "$n: anchor missing"; exit 1; }
	sed -i 's|spa_config_path = (char \*)"";|spa_config_path = getenv("LFU_ZTEST_CACHE") ? getenv("LFU_ZTEST_CACHE") : (char *)"";|' $F
	(cd $T && make -C lustre/utils libscan_zfs.la) > /tmp/lab1006-$n-make3.log 2>&1 ||
		{ echo "variant $n failed"; tail -5 /tmp/lab1006-$n-make3.log; exit 1; }
	cp $T/lustre/utils/scan_osd_zfs.so $P/lib/lustre/scan_osd_zfs.so.var
	strings $P/lib/lustre/scan_osd_zfs.so.var | grep -q LFU_ZTEST_CACHE || { echo "$n: variant lacks the env"; exit 1; }
	strings $P/lib/lustre/scan_osd_zfs.so.orig | grep -q LFU_ZTEST_CACHE && { echo "$n: orig has the env"; exit 1; }
	echo "  $n spa_evict_all: orig $(nm -D $P/lib/lustre/scan_osd_zfs.so.orig | grep -c ' U spa_evict_all') var $(nm -D $P/lib/lustre/scan_osd_zfs.so.var | grep -c ' U spa_evict_all')"
	echo "  $n PLUGIN_DIR: $(strings $P/lib/liblustreapi.so.1 | grep -m1 "$P/lib/lustre")"
	readelf -d $T/lustre/utils/.libs/lfs | grep -i path
	ls -la --time-style=+%T $T/lustre/utils/.libs/lfs $T/lustre/tests/.libs/llapi_scan_changelog_test | awk '{print $6, $NF}'
done
echo BUILD-OK
