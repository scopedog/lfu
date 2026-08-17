#!/bin/bash
# Probe: can this build's libext2fs open a filesystem with the Lustre
# EXT4_FEATURE_INCOMPAT_DIRDATA (0x1000) bit set?
#
# Every real Lustre MDT is formatted with dirdata (mkfs.lustre,
# libmount_utils_ldiskfs.c:635), so a scanner that cannot open such a
# filesystem is useless regardless of the rest of its design.
#
# Stock upstream e2fsprogs DEFINES the flag in ext2_fs.h but omits it from
# EXT2_LIB_FEATURE_INCOMPAT_SUPP, and EXT2_LIB_SOFTSUPP_INCOMPAT is (0), so
# EXT2_FLAG_SOFTSUPP_FEATURES provides no escape.  The WhamCloud fork
# (e2fsprogs-devel >= 1.47.3-wc1, already required by lustre.spec.in:354)
# supports it.
#
# Run this after switching libext2fs builds to confirm which you have.
#
# Usage: tests/dirdata_probe.sh [path-to-scanner]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SCAN="${1:-$ROOT/build/lfind-ldiskfs}"
WORK="$(mktemp -d)"
IMG="$WORK/dirdata.img"
trap 'rm -rf "$WORK"' EXIT

DIRDATA=0x1000

echo "==> creating image without dirdata (stock mke2fs cannot set it)"
truncate -s 32M "$IMG"
mke2fs -q -F -t ext4 -I 1024 -O ea_inode,project,64bit -b 4096 "$IMG" || exit 1

echo "==> setting EXT4_FEATURE_INCOMPAT_DIRDATA directly in the superblock"
OLD=$(python3 -c "
import struct
with open('$IMG','rb') as f:
    f.seek(1024+96)
    print(hex(struct.unpack('<I', f.read(4))[0]))")
NEW=$(python3 -c "print(hex($OLD | $DIRDATA))")
echo "    s_feature_incompat: $OLD -> $NEW"
debugfs -w -R "ssv feature_incompat $NEW" "$IMG" >/dev/null 2>&1

GOT=$(python3 -c "
import struct
with open('$IMG','rb') as f:
    f.seek(1024+96)
    print(hex(struct.unpack('<I', f.read(4))[0]))")
if [ "$GOT" != "$NEW" ]; then
	echo "    ERROR: bit not written (got $GOT); probe inconclusive" >&2
	exit 2
fi

echo
echo "==> stock dumpe2fs (no SOFTSUPP flag):"
if dumpe2fs -h "$IMG" >/dev/null 2>&1; then
	echo "    OPENS"
else
	echo "    REFUSES  <- expected with stock e2fsprogs"
fi

echo "==> lfind-ldiskfs (EXT2_FLAG_SOFTSUPP_FEATURES set):"
if [ ! -x "$SCAN" ]; then
	echo "    scanner not built: $SCAN" >&2
	exit 1
fi
if "$SCAN" -q "$IMG" >/dev/null 2>&1; then
	echo "    OPENS    <- this libext2fs supports dirdata (WhamCloud fork)"
	echo
	echo "RESULT: usable against real Lustre MDTs."
	exit 0
else
	echo "    REFUSES  <- stock libext2fs; SOFTSUPP does not help because"
	echo "                EXT2_LIB_SOFTSUPP_INCOMPAT is (0)"
	echo
	echo "RESULT: build against WhamCloud e2fsprogs (>= 1.47.3-wc1)."
	echo "        Lustre servers already install it — lustre.spec.in:354."
	exit 1
fi
