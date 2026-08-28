#!/bin/bash
# Are "this build cannot scan" and "this target was refused" two answers?
#
# conf-sanity test_165 skips itself when a build has no scan backend, and it
# reads that off the errno.  If a backend that IS there but refuses the
# target answers the same errno, the test skips on a node with a real MDT
# and a build that can scan it -- a pass that tested nothing.
#
# So: a device with an incompat feature no libext2fs knows, against a build
# whose plugin is installed, must NOT answer what a missing plugin answers.
set -e
L=${LTREE:-$HOME/lustre-160ac}
PLUG=${PLUG:-/usr/lib64/lustre/scan_ldiskfs.so}
IMG=${IMG:-/tmp/unsupp.img}
cd $L

rm -f $IMG
truncate -s 64M $IMG
mke2fs -q -t ext4 -F $IMG
python3 - "$IMG" <<'PY'
import struct, sys
f = open(sys.argv[1], "r+b")          # s_feature_incompat: superblock + 96
f.seek(1024 + 96); v = struct.unpack("<I", f.read(4))[0]
f.seek(1024 + 96); f.write(struct.pack("<I", v | 0x20000000))
f.close()
PY

# the loader tries PLUGIN_DIR before $LUSTRE, so the installed plugin wins
sudo -n cp -f $PLUG $PLUG.lab-save
sudo -n cp -f lustre/utils/scan_ldiskfs.so $PLUG

echo "== the backend is here and refuses the target"
./lustre/tests/llapi_scan_device_test -d $IMG 2>&1 | head -2

echo "== no backend at all"
sudo -n mv -f $PLUG /tmp/plug.away
sudo -n env -u LUSTRE ./lustre/tests/llapi_scan_device_test -d ${DEV:-/dev/vdb} \
	2>&1 | head -2
sudo -n mv -f /tmp/plug.away $PLUG

sudo -n mv -f $PLUG.lab-save $PLUG
rm -f $IMG
echo "The two lines above must not name the same errno."
