#!/bin/bash
# Stage 2 (round 17 variant): build the round-17 stack with osd-zfs.
# The branch arrives as a git bundle rather than a patch series.
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
git fetch -q /tmp/zfsguard.bundle 'refs/heads/r16-work:refs/heads/r17' -f
git checkout -q r17
echo "=== the series under test ==="
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
grep -q "^enable_zfs_scan='yes'" config.log && echo "zfs scan backend: enabled" || {
	echo "WARNING: enable_zfs_scan is not yes"; grep -i "zfs_scan" config.log | head -5; }

echo "=== make -j$(nproc) ==="
t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || { echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"

ls -la lustre/utils/scan_zfs.so || { echo "scan_zfs.so ABSENT"; exit 1; }
ldd lustre/utils/scan_zfs.so | grep -qE "libzpool" || { echo "does not link libzpool"; exit 1; }
echo "STAGE2 OK"
