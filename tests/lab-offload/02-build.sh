#!/bin/bash
# Build the lfs-find-offload stack (bundle ^47638add78) with ldiskfs, install.
set -e
KVER=$(uname -r)
cd ~
git config --global user.name "LFU lab"; git config --global user.email lfu@local
[ -d lustre-release ] || git clone -q https://github.com/lustre/lustre-release.git
cd lustre-release
git fetch -q origin master
git fetch -q ~/off.bundle lfs-find-offload:lfs-find-offload
git checkout -q -f lfs-find-offload
git clean -qfdx
git log --oneline -1
sh autogen.sh >/tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$KVER" >/tmp/configure.log 2>&1 || { tail -30 /tmp/configure.log; exit 1; }
grep -q "^ENABLE_LDISKFS='yes'" config.log || { echo "no ldiskfs"; exit 1; }
t0=$(date +%s)
make -j"$(nproc)" >/tmp/make.log 2>&1 || { echo BUILD FAILED; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"
nm -D --defined-only lustre/utils/.libs/liblustreapi.so.1.0.0 | grep -E "llapi_find_offload|llapi_scan_mount"
sudo make install >/tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo ldconfig; sudo depmod -a
sudo chown -R "$(id -un)": ~/lustre-release
/usr/sbin/lfs --version 2>/dev/null || lfs --version
lfs help find 2>&1 | grep -c offload
echo "STAGE2 OK"
