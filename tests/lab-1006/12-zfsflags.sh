#!/bin/bash
# 10-06 lab, stage 12 (as root on the clone VM): #1, "compile libscan_zfs.c
# as libzpool is built".  OLD = pnew 0a175c4191, NEW = znew bb7e771b7f.
#
# Z2: the struct layouts libscan_zfs.c is compiled against, under each
#     arm's ZFS_LIBZPOOL_INCLUDE, and whether the installed libzpool is a
#     ZFS_DEBUG build (its zfs_refcount_* are functions only under it).
# Z3: lfs find --device over an exported ZFS MDT and OST, several
#     predicates, OLD vs NEW: byte-identical answers.
set -u
OUT=/tmp/lab1006-zfsflags; ZT=/tmp/zfslab12
rm -rf $OUT $ZT; mkdir -p $OUT $ZT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "ABORT: pools imported"; zpool list; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
etc_before=$(md5sum /etc/zfs/zpool.cache 2>/dev/null)

# ---- Z2 ------------------------------------------------------------------
cat > $OUT/probe.c <<'PEOF'
struct page;
struct bio;
#include <stddef.h>
#include <stdio.h>
#include <sys/zfs_context.h>
#include <sys/dnode.h>
#include <sys/dbuf.h>
#include <sys/abd.h>
int main(void)
{
	printf("sizeof(zfs_refcount_t)=%zu sizeof(dnode_t)=%zu "
	       "offsetof(dn_num_slots)=%zu offsetof(dn_tx_holds)=%zu "
	       "offsetof(dn_holds)=%zu offsetof(dn_dbufs_mtx)=%zu "
	       "sizeof(dmu_buf_t)=%zu sizeof(abd_t)=%zu\n",
	       sizeof(zfs_refcount_t), sizeof(dnode_t),
	       offsetof(dnode_t, dn_num_slots), offsetof(dnode_t, dn_tx_holds),
	       offsetof(dnode_t, dn_holds), offsetof(dnode_t, dn_dbufs_mtx),
	       sizeof(dmu_buf_t), sizeof(abd_t));
	return 0;
}
PEOF
for n in pnew znew; do
	F=$(sed -n 's/^ZFS_LIBZPOOL_INCLUDE = //p' /tmp/lab1006-$n/lustre/utils/Makefile)
	echo "Z2 $n ZFS_LIBZPOOL_INCLUDE: $F"
	gcc -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 $F \
		-o $OUT/probe.$n $OUT/probe.c > $OUT/probe.$n.log 2>&1 ||
		{ echo "Z2 $n probe did not compile"; head -5 $OUT/probe.$n.log; continue; }
	echo "Z2 $n layout: $($OUT/probe.$n)"
	echo "Z2 $n libscan_zfs.c compiled with ZFS_DEBUG: $(grep -c 'DZFS_DEBUG.*libscan_zfs.c\|libscan_zfs.c.*DZFS_DEBUG' /tmp/lab1006-$n-make.log /tmp/lab1006-$n-make2.log | awk -F: '{s+=$2} END {print s}') compile lines"
done
echo "Z2 installed libzpool: $(rpm -qf /usr/lib64/libzpool.so.5), exports: $(nm -D /usr/lib64/libzpool.so.5 | grep -E ' [TDB] (zfs_refcount_create|zfs_refcount_add|zfs_refcount_remove|reference_tracking_enable)$' | awk '{print $3}' | tr '\n' ' ')"
echo "Z2 (zfs_refcount.h: under !ZFS_DEBUG zfs_refcount_create/_add/_remove are macros and reference_tracking_enable does not exist, so these exports mean libzpool was built with ZFS_DEBUG)"

# ---- Z3 ------------------------------------------------------------------
scan() {	# arm label dataset [args]
	local n=$1 label=$2 ds=$3; shift 3
	timeout 300 env LD_PRELOAD=/tmp/arm1006$n/lib/liblustreapi.so.1 \
		/tmp/lab1006-$n/lustre/utils/.libs/lfs find --device "$ds" --search $ZT "$@" \
		> $OUT/$label.$n.raw 2> $OUT/$label.$n.err
	echo $? > $OUT/$label.$n.rc
	sort $OUT/$label.$n.raw > $OUT/$label.$n.out
}
both() {	# label dataset [args]
	local label=$1; shift
	scan pnew $label "$@"; scan znew $label "$@"
	if cmp -s $OUT/$label.pnew.out $OUT/$label.znew.out &&
	   cmp -s $OUT/$label.pnew.err $OUT/$label.znew.err &&
	   cmp -s $OUT/$label.pnew.rc $OUT/$label.znew.rc; then
		echo "PASS Z3 $label [$*] identical: $(wc -l < $OUT/$label.znew.out) lines rc $(cat $OUT/$label.znew.rc) err[$(tr '\n' '|' < $OUT/$label.znew.err | cut -c1-120)]"
	else
		echo "FAIL Z3 $label [$*] differs"
		diff $OUT/$label.pnew.out $OUT/$label.znew.out | head -5
		diff $OUT/$label.pnew.err $OUT/$label.znew.err | head -5
	fi
}
for n in pnew znew; do
	echo "$n plugin: $(nm -D /tmp/arm1006$n/lib/lustre/scan_osd_zfs.so | grep -c ' U ') undefined syms, md5 $(md5sum < /tmp/arm1006$n/lib/lustre/scan_osd_zfs.so | cut -c1-12)"
done
cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=$ZT LUSTRE=/usr/lib64/lustre
bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q zfst-MDT0000 || { echo "ABORT: MDT did not mount"; tail -25 $OUT/llmount.txt; exit 4; }
MDTDS=$(lctl get_param -n osd-zfs.zfst-MDT0000.mntdev)
OSTDS=$(lctl get_param -n osd-zfs.zfst-OST0000.mntdev)
echo "MDT $MDTDS OST $OSTDS"
mkdir -p /mnt/zfst/d /mnt/zfst/e
for i in $(seq 1 60); do echo x > /mnt/zfst/d/f$i; done
for i in $(seq 1 20); do dd if=/dev/zero of=/mnt/zfst/e/g$i bs=64k count=$i status=none; done
ln /mnt/zfst/d/f1 /mnt/zfst/e/hl; mkdir /mnt/zfst/d/sub; ln -s f2 /mnt/zfst/d/sl
chown 500:500 /mnt/zfst/d/f3; chmod 600 /mnt/zfst/d/f4
sync; sleep 20
bash ./llmountcleanup.sh > $OUT/cleanup1.txt 2>&1
echo "exported: mounted $(mount -t lustre | wc -l), pools $(zpool list -H 2>/dev/null | wc -l)"
both mdt-all $MDTDS
both mdt-f $MDTDS --type f
both mdt-d $MDTDS --type d
both mdt-name $MDTDS -name 'f1*'
both mdt-uid $MDTDS -uid 500
both mdt-perm $MDTDS -perm 600
both mdt-links $MDTDS -links 2
both mdt-printf $MDTDS -printf '%LF %m %U %s\n'
both ost-all $OSTDS
both ost-size $OSTDS -size +256k
both ost-printf $OSTDS -printf '%LF %s\n'
rm -rf $ZT
[ "$etc_before" = "$(md5sum /etc/zfs/zpool.cache 2>/dev/null)" ] && echo "/etc/zfs/zpool.cache untouched"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "pools left: $(zpool list -H 2>/dev/null | wc -l)"
echo "== end $(date '+%F %T')"
echo "ZFSFLAGS RUN DONE"
