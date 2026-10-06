#!/bin/bash
# 10-06 lab, stage 3 (as root on the clone VM): Z1 (68163), spa_evict_all()
# after kernel_init().  ZFS 2.2.11 has no /boot/zfs/zpool.cache fallback,
# so the .var plugins take spa_config_path from $LFU_ZTEST_CACHE: a private
# cache file listing the kernel-held MDT pool, as 2.4 would load from /boot.
# /etc/zfs/zpool.cache is not touched.
set -u
OUT=/tmp/lab1006-zfs; ZT=/tmp/zfslab06; FAKE=$OUT/fake.cache
rm -rf $OUT $ZT; mkdir -p $OUT $ZT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "ABORT: pools imported"; zpool list; exit 2; }
etc_before=$(md5sum /etc/zfs/zpool.cache 2>/dev/null)
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null

plug() {	# arm orig|var
	cp /tmp/arm1006$1/lib/lustre/scan_osd_zfs.so.$2 /tmp/arm1006$1/lib/lustre/scan_osd_zfs.so
}
scan() {	# arm label dataset [args]
	local n=$1 label=$2 ds=$3; shift 3
	timeout 300 env LUSTRE=/tmp/lab1006-$n/lustre LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 \
		strace -f -e trace=openat -o $OUT/strace.$label.$n \
		/tmp/lab1006-$n/lustre/utils/.libs/lfs find --device "$ds" "$@" --type f \
		> $OUT/$label.$n.out 2> $OUT/$label.$n.err
	local rc=$?
	printf '%-14s %s exit=%-3s stdout=%-5s plugin=%s stderr: %s\n' "$label" "$n" "$rc" \
		"$(wc -l < $OUT/$label.$n.out)" \
		"$(grep 'scan_osd_zfs.so' $OUT/strace.$label.$n | grep -v ENOENT | grep -o '"[^"]*"' | head -1)" \
		"$(tr '\n' '|' < $OUT/$label.$n.err | cut -c1-160)"
	grep -q "openat.*$FAKE" $OUT/strace.$label.$n && echo "               ($n opened the fake cache)"
}

cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=$ZT LUSTRE=/usr/lib64/lustre
bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
mount -t lustre | grep -q zfst-MDT0000 || { echo "ABORT: MDT did not mount"; tail -25 $OUT/llmount.txt; exit 4; }
MDTDS=$(lctl get_param -n osd-zfs.zfst-MDT0000.mntdev); MDTPOOL=${MDTDS%%/*}
echo "MDT dataset $MDTDS"
mkdir -p /mnt/zfst/d; for i in $(seq 1 50); do echo x > /mnt/zfst/d/f$i; done
sync; sleep 20

echo "=== control: held, cache path empty (orig plugins): both must refuse EBUSY"
plug old orig; plug new orig
scan old held-orig $MDTDS; scan new held-orig $MDTDS

zpool set cachefile=$FAKE $MDTPOOL || { echo "ABORT: cachefile"; exit 5; }
echo "fake cache: $(stat -c %s $FAKE) bytes; lists $MDTPOOL: $(zdb -U $FAKE -C $MDTPOOL > /dev/null 2>&1 && echo yes || echo no)"
echo "=== Z1: held AND loaded from a cache file (var plugins, LFU_ZTEST_CACHE)"
plug old var; plug new var
export LFU_ZTEST_CACHE=$FAKE
for r in 1 2; do scan old z1-$r $MDTDS; scan new z1-$r $MDTDS; done
unset LFU_ZTEST_CACHE
echo "pool health after: $(zpool list -H -o name,health $MDTPOOL)"
zpool set cachefile=none $MDTPOOL

echo "=== control: exported, found with --search (orig plugins)"
plug old orig; plug new orig
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1
echo "cleanup rc=$?; mounted $(mount -t lustre | wc -l); pools $(zpool list -H 2>/dev/null | wc -l)"
if [ -z "$(zpool list -H 2>/dev/null)" ]; then
	scan old exported $MDTDS --search $ZT; scan new exported $MDTDS --search $ZT
	cmp -s <(sort $OUT/exported.old.out) <(sort $OUT/exported.new.out) &&
		echo "PASS exported: both arms give the same answer" || echo "FAIL exported: ARMS DIFFER"
	# and the var plugin with no cache env set is the orig
	plug new var
	scan new exported-var $MDTDS --search $ZT
	cmp -s <(sort $OUT/exported.new.out) <(sort $OUT/exported-var.new.out) &&
		echo "PASS var without env == orig" || echo "FAIL var without env differs"
	plug new orig
else
	echo "SKIPPED exported control"; zpool list
fi
rm -rf $ZT
[ "$etc_before" = "$(md5sum /etc/zfs/zpool.cache 2>/dev/null)" ] && echo "/etc/zfs/zpool.cache untouched"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "ZFS RUN DONE"
