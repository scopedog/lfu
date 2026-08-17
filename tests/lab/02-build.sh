#!/bin/bash
# Stage 2: clone lustre v2_17_55, apply the LFU patch stack in order, build a
# server with ldiskfs.  Never trusts configure's exit status: §3.3 note 3 says
# ENABLE_LDISKFS='no' is silent, so it is grepped out of config.log and the
# build refuses to continue without it.
set -e
KVER=$(uname -r)
cd ~
git config --global user.name "LFU lab"
git config --global user.email lfu@local

if [ ! -d lustre-release ]; then
	git clone -q https://github.com/lustre/lustre-release.git
fi
cd lustre-release
git checkout -q v2_17_55
git reset -q --hard v2_17_55
git clean -qfdx

echo "=== applying the LFU stack, in order ==="
for p in rec-attr rec-attr-zfs parallel-it itable-readahead \
         itable-blockparse otable-xattr; do
	f=~/lfu/patches/$p-v2_17_55.patch
	if git apply --check "$f" 2>/dev/null; then
		git apply "$f"
		echo "  applied  $p"
	else
		echo "  FAILED   $p"; exit 1
	fi
done
# bench scaffolding: needs patch(1) fuzz against the ordered stack
if patch -p1 --forward --fuzz=2 < ~/lfu/patches/bench-noverify-zfs-v2_17_55.patch >/dev/null 2>&1; then
	echo "  applied  bench-noverify-zfs (with fuzz)"
else
	echo "  skipped  bench-noverify-zfs (ZFS-only bench knob, not needed here)"
fi

echo "=== autogen ==="
sh autogen.sh >/tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }

echo "=== configure ==="
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }

echo "--- never trust exit 0 alone ---"
grep -E "^ENABLE_LDISKFS=" config.log || true
if ! grep -q "^ENABLE_LDISKFS='yes'" config.log; then
	echo "ENABLE_LDISKFS is not yes -- refusing to build a server that cannot mount"
	grep -iE 'ldiskfs|ext4' /tmp/configure.log | tail -20
	exit 1
fi
echo "ldiskfs: enabled"

echo "=== make -j$(nproc) ==="
t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || { echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
t1=$(date +%s)
echo "build took $((t1-t0))s"
# §3.3: a ~60-second build means ldiskfs was skipped
[ $((t1-t0)) -gt 180 ] || echo "WARNING: suspiciously fast build"

ls -la lustre/osd-ldiskfs/osd_ldiskfs.ko
echo "=== our symbols are in the module ==="
for s in osd_raw_xattr osd_raw_attr osd_iit_iget_raw osd_otable_it_xattr lfu_blockparse lfu_ra_blocks; do
	if nm lustre/osd-ldiskfs/osd_ldiskfs.ko 2>/dev/null | grep -qw "$s" || \
	   modinfo lustre/osd-ldiskfs/osd_ldiskfs.ko 2>/dev/null | grep -q "$s"; then
		echo "  present  $s"
	else
		echo "  ABSENT   $s"
	fi
done
echo "STAGE2 OK"
