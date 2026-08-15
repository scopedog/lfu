#!/bin/bash
# Build a synthetic ldiskfs-like MDT image with Lustre trusted.lma xattrs.
#
# Uses mke2fs + debugfs only — no root, no loop device, no mount.  The image
# mimics an MDT as formatted by mkfs.lustre (libmount_utils_ldiskfs.c:628-700,
# :883-890): 1024-byte inodes with ea_inode, dirdata, project quota.
#
# Objects created:
#   - namespace-visible files with FID_SEQ_NORMAL FIDs
#   - internal objects (FID_SEQ_LOCAL_FILE)      -> must be skipped
#   - an agent inode (LMAI_AGENT)                -> must be skipped
#   - an OST object (LMAC_FID_ON_OST)            -> must be skipped
#   - an encrypted file (LMAI_ENCRYPT)           -> emitted, flagged
#   - a file with LMAI_RELEASED                  -> must be classed "bad":
#       LMAI_RELEASED is vestigial and NOT in LMA_INCOMPAT_SUPP, so the kernel
#       rejects it too.  Real HSM state lives in trusted.hsm (HS_RELEASED).
#   - a file with an unsupported incompat bit    -> must be classed "bad"
#   - a file with no LMA at all                  -> must be classed "no-lma"
#   - files with distinct projid/blocks/atime for filter tests
#
# Usage: tests/mkimage.sh <output.img> [size]
set -euo pipefail

IMG="${1:?usage: mkimage.sh <output.img> [size]}"
SIZE="${2:-64M}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- LMA encoder -----------------------------------------------------------
# struct lustre_mdt_attrs { __u32 compat; __u32 incompat; lu_fid self; }
# lu_fid { __u64 f_seq; __u32 f_oid; __u32 f_ver; }   all little-endian, packed
mk_lma() {
	local out="$1" compat="$2" incompat="$3" seq="$4" oid="$5" ver="${6:-0}"
	python3 -c '
import struct, sys
out, compat, incompat, seq, oid, ver = sys.argv[1:7]
data = struct.pack("<IIQII", int(compat, 0), int(incompat, 0),
                   int(seq, 0), int(oid, 0), int(ver, 0))
open(out, "wb").write(data)
' "$out" "$compat" "$incompat" "$seq" "$oid" "$ver"
}

FID_SEQ_NORMAL=0x200000400
FID_SEQ_LOCAL_FILE=0x200000001
FID_SEQ_IDIF=0x100000000

LMAC_NOT_IN_OI=0x4
LMAC_FID_ON_OST=0x8
LMAI_RELEASED=0x1
LMAI_AGENT=0x2
LMAI_ENCRYPT=0x20
LMAI_UNSUPPORTED=0x40000000   # not in LMA_INCOMPAT_SUPP

echo "==> creating $IMG ($SIZE)"
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"

# Mirror mkfs.lustre's MDT feature set as closely as a file image allows.
#
# Omitted deliberately:
#   mmp     - needs a real block device
#   dirdata - stock mke2fs REFUSES to create it, even though stock libext2fs
#             recognises EXT4_FEATURE_INCOMPAT_DIRDATA (0x1000) when reading.
#             See tests/dirdata_probe.sh, which sets the bit directly to verify
#             the scanner can still open such a filesystem.
#
# metadata_csum is left at the mke2fs.conf default so the scanner's M8 warning
# path is exercised as it would be on a real target.
mke2fs -q -F -t ext4 \
	-I 1024 \
	-O ea_inode,project,quota,huge_file,large_dir,flex_bg,64bit,dir_nlink \
	-b 4096 \
	"$IMG"

# --- payload files ---------------------------------------------------------
echo "small"  > "$WORK/small"
head -c 200000 /dev/zero > "$WORK/big"

# --- create objects --------------------------------------------------------
# debugfs runs a script so every object is created in one pass.
{
	echo "cd /"
	echo "mkdir ROOT"
	for i in 1 2 3 4 5; do
		echo "write $WORK/small vis$i"
	done
	echo "write $WORK/big bigfile"
	echo "write $WORK/small internal1"
	echo "write $WORK/small agent1"
	echo "write $WORK/small ostobj1"
	echo "write $WORK/small released1"
	echo "write $WORK/small encrypted1"
	echo "write $WORK/small badincompat1"
	echo "write $WORK/small nolma1"
	echo "write $WORK/small proj1999"
	echo "write $WORK/small oldatime"
} > "$WORK/create.debugfs"

debugfs -w -f "$WORK/create.debugfs" "$IMG" >/dev/null 2>&1

# --- attach LMA xattrs -----------------------------------------------------
oid=100
{
	for i in 1 2 3 4 5; do
		mk_lma "$WORK/lma_vis$i" 0 0 $FID_SEQ_NORMAL $((oid + i)) >&2
		echo "ea_set -f $WORK/lma_vis$i vis$i trusted.lma"
	done
	mk_lma "$WORK/lma_big" 0 0 $FID_SEQ_NORMAL 200 >&2
	echo "ea_set -f $WORK/lma_big bigfile trusted.lma"

	mk_lma "$WORK/lma_int" $LMAC_NOT_IN_OI 0 $FID_SEQ_LOCAL_FILE 300 >&2
	echo "ea_set -f $WORK/lma_int internal1 trusted.lma"

	mk_lma "$WORK/lma_agent" 0 $LMAI_AGENT $FID_SEQ_NORMAL 301 >&2
	echo "ea_set -f $WORK/lma_agent agent1 trusted.lma"

	mk_lma "$WORK/lma_ost" $LMAC_FID_ON_OST 0 $FID_SEQ_IDIF 302 >&2
	echo "ea_set -f $WORK/lma_ost ostobj1 trusted.lma"

	mk_lma "$WORK/lma_rel" 0 $LMAI_RELEASED $FID_SEQ_NORMAL 400 >&2
	echo "ea_set -f $WORK/lma_rel released1 trusted.lma"

	mk_lma "$WORK/lma_enc" 0 $LMAI_ENCRYPT $FID_SEQ_NORMAL 401 >&2
	echo "ea_set -f $WORK/lma_enc encrypted1 trusted.lma"

	mk_lma "$WORK/lma_bad" 0 $LMAI_UNSUPPORTED $FID_SEQ_NORMAL 402 >&2
	echo "ea_set -f $WORK/lma_bad badincompat1 trusted.lma"

	# nolma1 deliberately gets no trusted.lma

	mk_lma "$WORK/lma_proj" 0 0 $FID_SEQ_NORMAL 500 >&2
	echo "ea_set -f $WORK/lma_proj proj1999 trusted.lma"

	mk_lma "$WORK/lma_old" 0 0 $FID_SEQ_NORMAL 501 >&2
	echo "ea_set -f $WORK/lma_old oldatime trusted.lma"
} > "$WORK/ea.debugfs" 2>/dev/null

debugfs -w -f "$WORK/ea.debugfs" "$IMG" >/dev/null 2>&1

# --- set projid and an old atime for filter tests --------------------------
{
	echo "sif proj1999 projid 1999"
	echo "sif oldatime atime 200001010000"
} > "$WORK/attr.debugfs"
debugfs -w -f "$WORK/attr.debugfs" "$IMG" >/dev/null 2>&1

echo "==> done: $IMG"
