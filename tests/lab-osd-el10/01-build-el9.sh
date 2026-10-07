#!/bin/bash
# 10-07: server build (ldiskfs + ZFS modules, -Werror) of the 68810 el10 fix
# on the el9 clone VM, at the series' bottom (68810) and its tip.
# Usage (as nishida on the clone VM): 01-build-el9.sh bot tip
set -u
K=5.14.0-611.42.1.el9_7.x86_64
for n in "$@"; do
	T=/tmp/osd1007-$n
	rm -rf $T; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/osd-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --enable-server \
		--with-linux=/usr/src/kernels/$K --enable-ldiskfs \
		--with-zfs=/usr/src/zfs-2.2.11 \
		--with-zfs-obj=/var/lib/dkms/zfs/2.2.11/$K/x86_64) \
		> /tmp/osd1007-$n-conf.log 2>&1 || { echo "configure $n failed"; tail -5 /tmp/osd1007-$n-conf.log; continue; }
	(cd $T && make -j4 modules) > /tmp/osd1007-$n-make.log 2>&1
	rc=$?
	echo "$n ($(cat /tmp/osd-$n.sha)) make modules rc=$rc errors: $(grep -c ' error: ' /tmp/osd1007-$n-make.log)"
	grep -m5 ' error: ' /tmp/osd1007-$n-make.log
	ls -la $T/lustre/osd-ldiskfs/osd_ldiskfs.ko $T/lustre/osd-zfs/osd_zfs.ko $T/lustre/lfu/lfu.ko 2>&1 | awk '{print "  "$NF" "$5}'
	grep -n "inode_get_[amc]time_sec\|i_[amc]time.tv_sec" $T/lustre/osd-ldiskfs/osd_scrub.c | head -3
done
echo BUILD-OSD-DONE
