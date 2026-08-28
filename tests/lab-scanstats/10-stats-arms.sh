#!/bin/bash
# Does the accounting assertion actually catch the double count?
#
# ss_seen == ss_filtered + ss_skipped + sum(ss_class) holds trivially on a
# quiescent device: nothing is skipped, so the arm that counts a skip twice
# and the arm that counts it once give the same answer.  So the control
# injects skips -- every 7th object takes the SKIP_XATTR path, the one the
# backend raises after the pre-filter has counted the object -- and then
# asks whether the assertion can tell the two arms apart.
#
#   ARM=fixed    inject only          -> test0 must PASS
#   ARM=control  inject + old counter -> test0 must FAIL
set -e
ARM=${ARM:-fixed}
L=${LTREE:-$HOME/lustre-160ac}
DEV=${DEV:-/dev/vdb}
cd $L
git checkout -q -- lustre/utils/libscan_ldiskfs.c \
		   lustre/utils/liblustreapi_scan_device.c
python3 ${CUT:-$HOME/cut-stats.py} "$ARM" "$L"
# the test links liblustreapi statically -- ldd says "not a dynamic
# executable" -- so a rebuild of lustre/utils alone leaves the old
# scan_sink_skip inside the test binary and the control arm silently runs
# the fixed code.  Relink it every time.
make -j"$(nproc)" -C lustre/utils > /tmp/arm-$ARM.log 2>&1 ||
	{ echo "BUILD FAILED"; grep -m5 error: /tmp/arm-$ARM.log; exit 1; }
rm -f lustre/tests/llapi_scan_device_test
make -j"$(nproc)" -C lustre/tests llapi_scan_device_test \
	>> /tmp/arm-$ARM.log 2>&1 ||
	{ echo "TEST BUILD FAILED"; tail -5 /tmp/arm-$ARM.log; exit 1; }
# The loader tries PLUGIN_DIR before $LUSTRE, so an installed
# scan_ldiskfs.so wins over the one just built and an armed backend is never
# loaded at all.  Put the armed one in its place for the run.
PLUG=${PLUG:-/usr/lib64/lustre/scan_ldiskfs.so}
sudo -n cp -f $PLUG $PLUG.lab-save
sudo -n cp -f lustre/utils/scan_ldiskfs.so $PLUG
set +e
sudo -n LUSTRE=$L/lustre ./lustre/tests/llapi_scan_device_test -d $DEV \
	> /tmp/arm-$ARM.out 2>&1
rc=$?
set -e
sudo -n mv -f $PLUG.lab-save $PLUG
git checkout -q -- lustre/utils/libscan_ldiskfs.c \
		   lustre/utils/liblustreapi_scan_device.c
grep -E "test0|seen, but" /tmp/arm-$ARM.out | head -4
echo "ARM=$ARM exit=$rc"
