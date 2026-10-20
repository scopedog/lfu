#!/bin/bash
# 10-20 stale-inode lab, stage 1 (as nishida on rhel9.7-server-mgs-mds-clone).
# Builds /tmp/stale-<n> from /tmp/stale-<n>.tgz: server modules (ldiskfs +
# ZFS) for every name; the full tree (utils, tests) too for the arms, which
# also get the lab-only lab_delay_us.  Nothing is installed: the arms run
# from their trees, so the VM's installed Lustre is left alone.
# Usage: 01-build.sh [-full] name...
set -u
K=5.14.0-611.42.1.el9_7.x86_64
FULL=0
[ "${1:-}" = -full ] && { FULL=1; shift; }
for n in "$@"; do
	T=/tmp/stale-$n
	rm -rf $T; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/stale-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	[ $FULL = 1 ] && /tmp/lab-delay.sh $T
	(cd $T && sh autogen.sh && ./configure --enable-server \
		--with-linux=/usr/src/kernels/$K --enable-ldiskfs \
		--with-zfs=/usr/src/zfs-2.2.11 \
		--with-zfs-obj=/var/lib/dkms/zfs/2.2.11/$K/x86_64 \
		--disable-iokit) > /tmp/stale-$n-conf.log 2>&1 ||
		{ echo "configure $n failed"; tail -5 /tmp/stale-$n-conf.log; continue; }
	if [ $FULL = 1 ]; then
		(cd $T && make -j4) > /tmp/stale-$n-make.log 2>&1
	else
		(cd $T && make -j4 modules) > /tmp/stale-$n-make.log 2>&1
	fi
	rc=$?
	echo "$n ($(cat /tmp/stale-$n.sha)) make rc=$rc errors=$(grep -c ' error: ' /tmp/stale-$n-make.log) warnings=$(grep -c ' warning: ' /tmp/stale-$n-make.log)"
	grep -m5 ' error: \| warning: ' /tmp/stale-$n-make.log
	for k in osd-ldiskfs/osd_ldiskfs.ko osd-zfs/osd_zfs.ko lfu/lfu.ko obdclass/obdclass.ko; do
		[ -f $T/lustre/$k ] || echo "  MISSING $k"
	done
	[ $FULL = 1 ] && { gcc -O2 -I$T/include/uapi -o $T/ringdump /tmp/ringdump.c &&
		gcc -O2 -I$T/lustre/include -I$T/include -I$T/include/uapi \
			-include $T/config.h -o $T/mountdump /tmp/mountdump.c \
			-L$T/lustre/utils/.libs -llustreapi \
			-Wl,-rpath,$T/lustre/utils/.libs || echo "  harness build FAILED"; }
	[ $FULL = 1 ] && rm -rf $T/.git
done
echo BUILD-DONE
