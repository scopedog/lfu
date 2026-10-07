#!/bin/bash
# 10-07 lab, stage 3 (as root on the clone VM): Z1 (68163), a non-root
# caller whose vdevs it cannot read gets EACCES, not ENOENT.  This VM has
# ZFS 2.2.11, where the old lpc_error test works too: the arm shows the new
# lpc_open_access_error test does not regress.  The 2.4 overwrite itself is
# read from the ZFS source (zutil_import.c, zpool_find_config()), and
# reproduced by Z24 with a plugin that overwrites lpc_error the same way.
# Needs scan_osd_zfs.so.{orig,z24} in each arm (built by hand, see BOARD).
set -u
OUT=/tmp/lab1007-zfs; ZT=/tmp/zfslab07
rm -rf $OUT $ZT; mkdir -p $OUT $ZT; chmod 755 $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') zfs $(cat /sys/module/zfs/version 2>/dev/null)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "ABORT: pools imported"; zpool list; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null

scan() {	# arm label user dataset [args]
	local n=$1 label=$2 who=$3 ds=$4; shift 4
	local cmd="env LUSTRE=/tmp/lab1007-$n/lustre LD_PRELOAD=/tmp/arm1007$n/lib/liblustreapi.so.1 /tmp/lab1007-$n/lustre/utils/.libs/lfs find --device $ds $* --type f"
	if [ $who = root ]; then
		timeout 300 $cmd > $OUT/$label.$n.out 2> $OUT/$label.$n.err
	else
		timeout 300 runuser -u $who -- $cmd > $OUT/$label.$n.out 2> $OUT/$label.$n.err
	fi
	local rc=$?
	printf '%-10s %s %-7s exit=%-3s stdout=%-5s stderr: %s\n' "$label" "$n" "$who" "$rc" \
		"$(wc -l < $OUT/$label.$n.out)" "$(tr '\n' '|' < $OUT/$label.$n.err | cut -c1-200)"
	eval "rc_${label//-/_}_$n=$rc"
}

cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=$ZT LUSTRE=/usr/lib64/lustre
bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q zfst-MDT0000 || { echo "ABORT: MDT did not mount"; tail -25 $OUT/llmount.txt; exit 4; }
MDTDS=$(lctl get_param -n osd-zfs.zfst-MDT0000.mntdev)
echo "MDT dataset $MDTDS"
mkdir -p /mnt/zfst/d; for i in $(seq 1 20); do echo x > /mnt/zfst/d/f$i; done
sync; sleep 10
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1
echo "cleanup rc=$?; mounted $(mount -t lustre | wc -l); pools $(zpool list -H 2>/dev/null | wc -l)"
[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "ABORT: pools still imported"; exit 5; }
ls -l $ZT
chmod 755 $ZT; chmod 600 $ZT/* 2>/dev/null

for n in old new; do scan $n root root $MDTDS --search $ZT; done
for n in old new; do scan $n user nishida $MDTDS --search $ZT; done
# a name that is in no label, as the same user: ENOENT is right there only
# when nothing was unreadable, so this one is EACCES as well
for n in old new; do scan $n nopool nishida nosuchpool/mdt --search $ZT; done
# Z24: each arm's plugin rebuilt with lpc_error overwritten after
# zpool_find_config(), as ZFS 2.4 leaves it.  OLD should fall to ENOENT.
for n in old new; do cp /tmp/arm1007$n/lib/lustre/scan_osd_zfs.so.z24 /tmp/arm1007$n/lib/lustre/scan_osd_zfs.so; done
for n in old new; do scan $n z24 nishida $MDTDS --search $ZT; done
for n in old new; do cp /tmp/arm1007$n/lib/lustre/scan_osd_zfs.so.orig /tmp/arm1007$n/lib/lustre/scan_osd_zfs.so; done
# readable vdevs, missing pool: ENOENT for both
chmod 644 $ZT/*
for n in old new; do scan $n readable nishida nosuchpool/mdt --search $ZT; done

[ $rc_root_new = 0 ] && [ -s $OUT/root.new.out ] && pass=1 || pass=0
[ $pass = 1 ] && echo "PASS root reads the pool (new)" || echo "FAIL root new"
cmp -s <(sort $OUT/root.old.out) <(sort $OUT/root.new.out) && echo "PASS root: arms agree" || echo "FAIL root: arms differ"
grep -q "Permission denied" $OUT/user.new.err && echo "PASS user: new says EACCES" || echo "FAIL user: new [$(head -1 $OUT/user.new.err)]"
grep -q "Permission denied" $OUT/user.old.err && echo "  user: old says EACCES too (2.2)" || echo "  user: old [$(head -1 $OUT/user.old.err)]"
grep -q "Permission denied" $OUT/z24.new.err && echo "PASS z24: new still says EACCES" || echo "FAIL z24: new [$(head -1 $OUT/z24.new.err)]"
grep -q "No such file" $OUT/z24.old.err && echo "PASS z24: old falls to ENOENT (the 2.4 defect reproduced)" || echo "FAIL z24: old [$(head -1 $OUT/z24.old.err)]"
grep -q "No such file" $OUT/readable.new.err && echo "PASS readable missing pool: new says ENOENT" || echo "FAIL readable: new [$(head -1 $OUT/readable.new.err)]"
rm -rf $ZT
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "ZFS RUN DONE"
