#!/bin/bash
# Build Jinshan Xiong's LU-20591 series at the change ref for 68020, which
# carries 68018 and 68019 as ancestors.  Second tree on the same box, same
# configure flags as ours, so the only difference between rounds is which
# modules are installed.
set -e
cd ~
if [ ! -d lustre-xiong ]; then
	git clone -q --shared ~/lustre-release lustre-xiong
fi
cd lustre-xiong
git fetch -q https://review.whamcloud.com/fs/lustre-release refs/changes/20/68020/1
git checkout -q FETCH_HEAD
echo "=== HEAD ==="
git log --oneline -4
echo "=== confirm 68018/68019 are ancestors ==="
git log --oneline -4 | grep -c 'LU-20591' || true

sh autogen.sh > /tmp/x-autogen.log 2>&1 || { tail -20 /tmp/x-autogen.log; exit 1; }
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$(uname -r)" > /tmp/x-configure.log 2>&1 || {
	tail -30 /tmp/x-configure.log; exit 1; }
grep -E "^ENABLE_LDISKFS=" config.log
grep -q "^ENABLE_LDISKFS='yes'" config.log || { echo "ldiskfs off - refusing"; exit 1; }

t0=$(date +%s)
make -j"$(nproc)" > /tmp/x-make.log 2>&1 || { echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/x-make.log | head -30; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"
ls -la lustre/osd-ldiskfs/osd_ldiskfs.ko lustre/utils/lctl
echo "=== their filter symbols present? ==="
for s in scrub_iterate_objects scrub_iter_filter_match; do
	if grep -qr "$s" lustre/obdclass/scrub.c lustre/include/lustre_scrub.h 2>/dev/null; then
		echo "  source has  $s"
	fi
done
strings lustre/utils/lctl | grep -c 'iterate_objects' || true
echo "THEIRS BUILT"
