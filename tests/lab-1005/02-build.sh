#!/bin/bash
# Stage 2: build the fix-1005 stack (new/) and, for the A/B arms, the tip
# before the lreview(2) fixes (old/).  Usage: 02-build.sh ldiskfs|zfs
#
# Both trees get the same configure.  The old tree is never installed: its
# lfs runs from the build tree, and liblustreapi -- where every fix lives --
# comes from that tree's .libs through the libtool wrapper.
set -e
FS=$1
BASE=$(cat ~/lab/base.txt)
KVER=$(uname -r)
git config --global user.name "LFU lab"
git config --global user.email lfu@local

case $FS in
ldiskfs) CONF="--enable-server --enable-ldiskfs --disable-zfs"; WANT=ENABLE_LDISKFS ;;
zfs)     CONF="--enable-server --with-zfs --disable-ldiskfs"; WANT=ENABLE_ZFS ;;
*) echo "usage: $0 ldiskfs|zfs"; exit 1 ;;
esac

build() {	# build <dir> <patchdir>
	local d=$1 p=$2
	cd ~
	[ -d $d ] || git clone -q https://github.com/lustre/lustre-release.git $d
	cd $d
	git fetch -q origin
	git checkout -q "$BASE"; git reset -q --hard "$BASE"; git clean -qfdx
	git am -q $p/*.patch
	echo "=== $d: $(git log --oneline -1)"
	git log --oneline "$BASE"..HEAD | wc -l
	sh autogen.sh > /tmp/autogen.$d.log 2>&1 || { tail -20 /tmp/autogen.$d.log; exit 1; }
	./configure $CONF --with-linux="/usr/src/kernels/$KVER" \
		> /tmp/configure.$d.log 2>&1 || { tail -30 /tmp/configure.$d.log; exit 1; }
	grep -q "^$WANT='yes'" config.log || { echo "$d: $WANT is not yes"; exit 1; }
	local t0=$(date +%s)
	make -j"$(nproc)" > /tmp/make.$d.log 2>&1 || {
		echo "$d: BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.$d.log | head -40; exit 1; }
	echo "$d: build took $(( $(date +%s) - t0 ))s"
}

build lustre-release ~/lab/new
build lustre-old ~/lab/old

cd ~/lustre-release
sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo ldconfig
sudo depmod -a
sudo chown -R "$(id -un):$(id -gn)" ~/lustre-release
# The two must differ where the fixes are, or the A/B proves nothing.
cmp -s ~/lustre-release/lustre/utils/.libs/liblustreapi.so \
	~/lustre-old/lustre/utils/.libs/liblustreapi.so &&
	{ echo "old and new liblustreapi are identical"; exit 1; }
grep -c "find_since_seen" ~/lustre-release/lustre/utils/liblustreapi_pfind.c
! grep -q "find_since_seen" ~/lustre-old/lustre/utils/liblustreapi_pfind.c
echo "STAGE2 OK"
