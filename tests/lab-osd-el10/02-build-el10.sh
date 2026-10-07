#!/bin/bash
# 10-07: the 68810 el10 fix on el10 (kernel-devel 6.12.0-124.56.1.el10_1,
# the newest el10 the tree has an ldiskfs series for), modules only.
#   oldbot = 83ce8639ae, 68810 as pushed: should fail on i_atime, as
#            Artem saw.  bot / tip = the fixed bottom and tip.
# fs/ext4 is copied into the kernel-devel tree from Rocky's
# kernel-6.12.0-124.56.1.el10_1.src.rpm (the RHEL CDN is unreachable here).
# Usage (as nishida on rhel10.2-client-clone): 02-build-el10.sh oldbot bot tip
set -u
K=6.12.0-124.56.1.el10_1.x86_64
L=/usr/src/kernels/$K
if [ ! -e $L/fs/ext4/super.c ]; then
	sudo tar -C $L/fs -xzf /tmp/ext4-124.56.1.tgz || exit 1
fi
for n in "$@"; do
	T=/tmp/osd1007-$n
	rm -rf $T; mkdir -p $T
	tar -C $T --strip-components=1 -xzf /tmp/osd-$n.tgz || exit 1
	echo "LUSTRE_VERSION = 2.17.58" > $T/LUSTRE-VERSION-FILE
	(cd $T && sh autogen.sh && ./configure --enable-server --enable-ldiskfs \
		--with-linux=$L --without-zfs --disable-utils --disable-tests \
		--disable-iokit) > /tmp/osd1007-$n-conf.log 2>&1 ||
		{ echo "configure $n failed"; tail -8 /tmp/osd1007-$n-conf.log; continue; }
	echo "$n ldiskfs series: $(grep -m1 'LDISKFS_SERIES\|ldiskfs series' /tmp/osd1007-$n-conf.log | cut -c1-120)"
	(cd $T && make -k -j4 modules) > /tmp/osd1007-$n-make.log 2>&1
	rc=$?
	echo "$n ($(cat /tmp/osd-$n.sha)) make modules rc=$rc errors: $(grep -c ' error: ' /tmp/osd1007-$n-make.log)"
	grep ' error: ' /tmp/osd1007-$n-make.log | sed 's|/tmp/osd1007-[a-z]*/||' | sort -u | head -8
	for k in ldiskfs/ldiskfs.ko lustre/osd-ldiskfs/osd_ldiskfs.ko lustre/lfu/lfu.ko; do
		[ -f $T/$k ] && echo "  built $k" || echo "  missing $k"
	done
done
echo BUILD-EL10-DONE
