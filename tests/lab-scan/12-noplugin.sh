#!/bin/bash
# The Janitor's configuration: no shared libraries, so PLUGIN_DIR is off and
# the backend is linked in.  This is the build that caught the missing static
# archive symbols, and the one that failed on scan_backend_name.
set -e
L=/home/nishida/lustre-release
KVER=$(uname -r)
cd $L
cd $L/lustre/tests && ./llmountcleanup.sh > /dev/null 2>&1 || true
cd $L
make distclean > /dev/null 2>&1 || true
./configure --enable-server --enable-ldiskfs --disable-zfs --disable-shared \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/conf-np.log 2>&1 || {
	tail -30 /tmp/conf-np.log; exit 1; }
grep -E "^ENABLE_LDISKFS=|^enable_shared=" config.log | head -3
echo "=== PLUGIN_DIR in config.h:"
grep -n "PLUGIN_DIR" config.h || echo "  not defined -- backend is linked in"
# the whole tree, not just lustre/utils: a distcleaned tree has no
# libcfs.la, and liblustreapi.la links against it
echo "=== building"
make -j"$(nproc)" > /tmp/make-np.log 2>&1 || {
	echo "NOPLUGIN BUILD FAILED"
	grep -nE 'error:|Error [0-9]|No rule to make target' /tmp/make-np.log | head -20; exit 1; }
echo "=== the symbol the Janitor missed last time"
nm liblustreapi.a 2>/dev/null | grep -c scan_ldiskfs_open || true
nm lustre/utils/.libs/liblustreapi.a 2>/dev/null | grep -c "T scan_ldiskfs_open" || true
echo "=== warnings, if any"
grep -nE "warning:" /tmp/make-np.log | head -10 || echo "  none"
echo "STAGE12 OK"
