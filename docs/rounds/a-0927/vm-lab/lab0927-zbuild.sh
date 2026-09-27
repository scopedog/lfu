#!/bin/bash
# 09-27: ZFS-capable userspace arms for 68163 (dn_num_slots in so_blocks).
# Same tarballs as lab0927-build.sh; trees ~/lab0927z-<arm>, prefix
# ~/arm0927z<arm>.  libmount_utils_zfs.c does not build without the server
# definitions (upstream), hence make -k, then the three targets asserted.
set -u
for n in "$@"; do
	T=$HOME/lab0927z-$n; P=$HOME/arm0927z$n
	rm -rf $T $P; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/lab0927-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --prefix=$P --disable-modules --disable-iokit --with-zfs=/usr/src/zfs-2.2.11) > $HOME/lab0927z-$n-conf.log 2>&1 || { echo "configure $n failed"; exit 1; }
	grep -E "ZFS_SCAN_ENABLED_TRUE|^ZFS_ENABLED_TRUE" $T/config.status | head -2
	(cd $T && make -k -j4) > $HOME/lab0927z-$n-make.log 2>&1
	(cd $T && make -C lustre/utils liblustreapi.la lfs libscan_zfs.la) > $HOME/lab0927z-$n-make2.log 2>&1 || { echo "make targets $n failed"; grep -m5 " error: " $HOME/lab0927z-$n-make2.log; exit 1; }
	echo "  $n make -k errors: $(grep -c ' error: ' $HOME/lab0927z-$n-make.log) ($(grep ' error: ' $HOME/lab0927z-$n-make.log | sed 's/:.*//' | sort -u | tr '\n' ' '))"
	mkdir -p $P/lib/lustre
	cp -a $T/lustre/utils/.libs/liblustreapi.so* $P/lib/
	cp $T/lustre/utils/scan_osd_zfs.so $P/lib/lustre/
	ls -la --time-style=+%T $T/lustre/utils/.libs/lfs $P/lib/liblustreapi.so.1.0.0 $P/lib/lustre/scan_osd_zfs.so | awk '{print $6, $NF}'
	echo "  PLUGIN_DIR: $(strings $P/lib/liblustreapi.so.1 | grep -m1 "$P/lib/lustre")"
	objcopy -O binary --only-section=.text $P/lib/lustre/scan_osd_zfs.so /tmp/lab0927z-$n.text
done
cmp -s /tmp/lab0927z-new.text /tmp/lab0927z-old.text && echo "  WARNING: the two zfs plugins have the same .text" || echo "  the two zfs plugins' .text differ"
echo ZBUILD-OK
