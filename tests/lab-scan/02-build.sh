#!/bin/bash
# Stage 2: build lustre-release at the LU-20603 base commit with the scanner
# API patch applied.  No LFU kernel patch stack here -- this tests a userspace
# library addition, so the tree is otherwise stock.
set -e
KVER=$(uname -r)
BASE=$(cat ~/base.txt)
cd ~
git config --global user.name "LFU lab"
git config --global user.email lfu@local

if [ ! -d lustre-release ]; then
	git clone -q https://github.com/lustre/lustre-release.git
fi
cd lustre-release
git fetch -q origin master
git checkout -q "$BASE"
git reset -q --hard "$BASE"
git clean -qfdx

echo "=== applying the LU-20603 patch ==="
git am ~/*.patch
git log --oneline -1

echo "=== autogen ==="
sh autogen.sh >/tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }

echo "=== configure ==="
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }

grep -E "^ENABLE_LDISKFS=" config.log || true
if ! grep -q "^ENABLE_LDISKFS='yes'" config.log; then
	echo "ENABLE_LDISKFS is not yes -- refusing to build a server that cannot mount"
	exit 1
fi
echo "ldiskfs: enabled"

echo "=== make -j$(nproc) ==="
t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || {
	echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"

echo "=== the symbol we came for ==="
nm -D --defined-only lustre/utils/.libs/liblustreapi.so.1.0.0 | grep llapi_scan_namespace

sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo ldconfig
sudo depmod -a
echo "STAGE2 OK"
