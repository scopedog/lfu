#!/bin/bash
# Stage 2 (ZFS): clone v2_17_55, apply the LFU stack, build a server with
# osd-zfs.  --disable-ldiskfs deliberately: this lab is only about the ZFS
# tier-1 path, and dropping ldiskfs halves the build.
#
# `--with-zfs` must be BARE.  --with-zfs=/usr/src/zfs-X makes configure look
# for the object dir at <path>/$LINUXRELEASE and fail; bare autodetects the
# DKMS layout (zfs-mdt-verification-2026-08-07.md §1).  configure exits 0
# either way, so ENABLE_ZFS is grepped out of config.log.
set -e
KVER=$(uname -r)
cd ~
git config --global user.name "LFU lab"
git config --global user.email lfu@local
[ -d lustre-release ] || git clone -q https://github.com/lustre/lustre-release.git
cd lustre-release
git checkout -q v2_17_55; git reset -q --hard v2_17_55; git clean -qfdx

echo "=== applying the LFU stack, in order ==="
for p in rec-attr rec-attr-zfs parallel-it itable-readahead \
         itable-blockparse otable-xattr; do
	f=~/lfu/patches/$p-v2_17_55.patch
	git apply --check "$f" 2>/dev/null || { echo "  FAILED   $p"; exit 1; }
	git apply "$f"; echo "  applied  $p"
done

echo "=== autogen ==="
sh autogen.sh > /tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }

echo "=== configure ==="
./configure --enable-server --with-zfs --disable-ldiskfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }
grep -E "^ENABLE_ZFS=" config.log || true
grep -q "^ENABLE_ZFS='yes'" config.log || {
	echo "ENABLE_ZFS is not yes -- refusing to build a server that cannot mount"
	grep -iE 'zfs' /tmp/configure.log | tail -25; exit 1; }
echo "zfs: enabled"

echo "=== make -j$(nproc) ==="
t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || { echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"

ls -la lustre/osd-zfs/osd_zfs.ko
echo "=== the new symbols must be in osd_zfs.ko ==="
for s in osd_otable_it_xattr osd_otable_it_attr __osd_xattr_load_by_oid_keep; do
	nm lustre/osd-zfs/osd_zfs.ko | grep -qw "$s" && echo "  present  $s" || { echo "  ABSENT   $s"; exit 1; }
done
echo "=== warnings from our hunks, if any ==="
# NOT `grep ... | head || echo none`: the pipeline's status is head's, so the
# fallback never fires and "no warnings" is indistinguishable from "warnings
# hidden".  Capture first, then decide.
w=$(grep -iE "osd_scrub\.c.*(warning|error)" /tmp/make.log | head -20)
[ -n "$w" ] && echo "$w" || echo "  (none)"
echo "STAGE2 OK"
