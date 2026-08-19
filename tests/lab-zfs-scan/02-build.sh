#!/bin/bash
# Stage 2: clone master at the series' base, apply the eight LFU changes, and
# build a server with osd-zfs.  --disable-ldiskfs deliberately: the ldiskfs
# backend is already proved on a real MDT, and dropping it halves the build.
#
# --with-zfs must be BARE: a path makes configure look for the object dir at
# <path>/$LINUXRELEASE.  configure exits 0 either way, so ENABLE_ZFS is
# grepped out of config.log.
set -e
BASE=5afbab284e9cc45b2635213d99d23364e1abbc05
KVER=$(uname -r)
cd ~
git config --global user.name "LFU lab"
git config --global user.email lfu@local
[ -d lustre-release ] || git clone -q https://github.com/lustre/lustre-release.git
cd lustre-release
git fetch -q origin
git checkout -q "$BASE"; git reset -q --hard "$BASE"; git clean -qfdx

echo "=== applying the LFU series ==="
git am ~/patches/*.patch > /tmp/am.log 2>&1 || { tail -30 /tmp/am.log; exit 1; }
git log --oneline "$BASE"..HEAD | tac

echo "=== autogen ==="
sh autogen.sh > /tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }

echo "=== configure ==="
./configure --enable-server --with-zfs --disable-ldiskfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }
grep -q "^ENABLE_ZFS='yes'" config.log || {
	echo "ENABLE_ZFS is not yes -- refusing to build a server that cannot mount"
	grep -iE 'zfs' /tmp/configure.log | tail -25; exit 1; }
echo "zfs: enabled"

echo "=== make -j$(nproc) ==="
t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || { echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"

echo "=== the ZFS scan plugin must have been built and must link libzpool ==="
ls -la lustre/utils/scan_zfs.so || { echo "scan_zfs.so ABSENT"; exit 1; }
ldd lustre/utils/scan_zfs.so | grep -E "libzpool|libnvpair" || { echo "does not link libzpool"; exit 1; }
for s in scan_zfs_open scan_zfs_close scan_zfs_worker_init scan_zfs_worker_fini scan_zfs_scan_chunk; do
	nm -D lustre/utils/scan_zfs.so | grep -qw "$s" && echo "  present  $s" || { echo "  ABSENT   $s"; exit 1; }
done

echo "=== and liblustreapi itself must link NEITHER backend library ==="
if ldd lustre/utils/.libs/liblustreapi.so | grep -E "libzpool|libext2fs"; then
	echo "liblustreapi links a backend library -- the plugin split is broken"; exit 1
fi
echo "  liblustreapi links neither libzpool nor libext2fs"

w=$(grep -iE "libscan_zfs\.c.*(warning|error)" /tmp/make.log | head -20)
[ -n "$w" ] && echo "$w" || echo "  (no warnings from libscan_zfs.c)"
echo "STAGE2 OK"
