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

# --- tier-1 xattr encoders -------------------------------------------------
# All little-endian and packed, matching src/lfu_lustre.h.  These exist so the
# tier-1 predicates can be tested without a Lustre filesystem: what a real MDT
# writes here is exactly these bytes.
mk_som() {
	local out="$1" valid="$2" size="$3" blocks="$4"
	python3 -c '
import struct, sys
out, valid, size, blocks = sys.argv[1:5]
# lsa_valid u16, lsa_reserved[3] u16, lsa_size u64, lsa_blocks u64
open(out, "wb").write(struct.pack("<4H2Q", int(valid, 0), 0, 0, 0,
                                  int(size, 0), int(blocks, 0)))
' "$out" "$valid" "$size" "$blocks"
}

# mk_lov <out> <pattern> <stripe_size> <pool|-> <ost_idx...>
# Writes v1 when no pool is given, v3 when one is.
mk_lov() {
	python3 -c '
import struct, sys
out, pattern, ssize, pool = sys.argv[1:5]
osts = [int(x, 0) for x in sys.argv[5:]]
LOV_MAGIC_V1 = 0x0BD10BD0
LOV_MAGIC_V3 = 0x0BD30BD0
v3 = pool != "-"
magic = LOV_MAGIC_V3 if v3 else LOV_MAGIC_V1
hdr = struct.pack("<II16sIHH", magic, int(pattern, 0), b"\0" * 16,
                  int(ssize, 0), len(osts), 0)
if v3:
    hdr += pool.encode().ljust(16, b"\0")
body = b"".join(struct.pack("<16sII", b"\0" * 16, 0, o) for o in osts)
open(out, "wb").write(hdr + body)
' "$@"
}

# mk_lov_comp <out> <stripe_size> <"pattern:ost,ost" ...>
# A composite (PFL) layout: one lov_comp_md_v1 header, one entry per
# component, and each component's own v1 blob appended after the entry array.
mk_lov_comp() {
	python3 -c '
import struct, sys
out, ssize = sys.argv[1:3]
comps = [c.split(":") for c in sys.argv[3:]]
LOV_MAGIC_V1 = 0x0BD10BD0
LOV_MAGIC_COMP_V1 = 0x0BD60BD0
ENT = 48
HDR = 32
blobs, start = [], HDR + ENT * len(comps)
for pattern, osts in comps:
    osts = [int(x, 0) for x in osts.split(",") if x != ""]
    blob = struct.pack("<II16sIHH", LOV_MAGIC_V1, int(pattern, 0), b"\0" * 16,
                       int(ssize, 0), len(osts), 0)
    blob += b"".join(struct.pack("<16sII", b"\0" * 16, 0, o) for o in osts)
    blobs.append(blob)
ents, off, ext = b"", start, 0
for i, blob in enumerate(blobs):
    end = (1 << 64) - 1 if i == len(blobs) - 1 else ext + (1 << 30)
    ents += struct.pack("<IIQQIIIQ4B", i + 1, 0, ext, end, off, len(blob),
                        0, 0, 0, 0, 0, 0)
    off += len(blob)
    ext = end
total = start + sum(len(b) for b in blobs)
hdr = struct.pack("<IIIHHHBBHHQ", LOV_MAGIC_COMP_V1, total, 0, 0,
                  len(blobs), 0, 0, 0, 0, 0, 0)
open(out, "wb").write(hdr + ents + b"".join(blobs))
' "$@"
}

mk_lmv() {
	local out="$1" count="$2" hash="$3"
	python3 -c '
import struct, sys
out, count, hashtype = sys.argv[1:4]
LMV_MAGIC_V1 = 0x0CD20CD0
open(out, "wb").write(struct.pack("<8IQ16s", LMV_MAGIC_V1, int(count, 0), 0,
                                  int(hashtype, 0), 0, 0, 0, 0, 0, b""))
' "$out" "$count" "$hash"
}

# mk_linkea <out> <name...> — header in host order (linkea.c:23), lee_reclen
# big-endian and unaligned (linkea.c:97).
mk_linkea() {
	python3 -c '
import struct, sys
out = sys.argv[1]
names = sys.argv[2:]
LINK_EA_MAGIC = 0x11EAF1DF
recs = b""
for n in names:
    nb = n.encode()
    reclen = 2 + 16 + len(nb)
    recs += bytes([(reclen >> 8) & 0xff, reclen & 0xff]) + b"\0" * 16 + nb
hdr = struct.pack("=IIQII", LINK_EA_MAGIC, len(names), 24 + len(recs), 0, 0)
open(out, "wb").write(hdr + recs)
' "$@"
}

SOM_FL_LAZY=0x4
LOV_PATTERN_RAID0=0x1
LOV_PATTERN_MDT=0x100
LOV_PATTERN_F_RELEASED=0x80000000
LMV_HASH_FNV_1A_64=2

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
	# tier-1 fixtures (docs/filter-levels.md §5.2)
	echo "write $WORK/small striped1"
	echo "write $WORK/small striped_nosom"
	echo "write $WORK/small pooled1"
	echo "write $WORK/small hsmrel1"
	echo "write $WORK/small comp1"
	echo "write $WORK/small named1"
	echo "write $WORK/small immutable1"
	echo "write $WORK/small widelov1"
	echo "mkdir stripedir1"
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

	# --- tier-1 fixtures ------------------------------------------------
	#
	# The point of striped1: on a real MDT a striped file's own i_blocks is
	# single digits while its data is on the OSTs, so `--dev-blocks +1G`
	# must miss it and `--blocks +1G` must find it.  2 GiB of data in SOM,
	# a few blocks of inode in the inode.
	oid=600
	for f in striped1 striped_nosom pooled1 hsmrel1 comp1 named1 \
		 immutable1 widelov1 stripedir1; do
		oid=$((oid + 1))
		mk_lma "$WORK/lma_$f" 0 0 $FID_SEQ_NORMAL $oid >&2
		echo "ea_set -f $WORK/lma_$f $f trusted.lma"
	done

	mk_lov "$WORK/lov_striped1" $LOV_PATTERN_RAID0 1048576 - 3 7 >&2
	echo "ea_set -f $WORK/lov_striped1 striped1 trusted.lov"
	mk_som "$WORK/som_striped1" $SOM_FL_LAZY $((2 * 1024 * 1024 * 1024)) \
		$((2 * 1024 * 1024 * 1024 / 512)) >&2
	echo "ea_set -f $WORK/som_striped1 striped1 trusted.som"

	# Striped, but never closed since SOM was enabled: the undecided case.
	mk_lov "$WORK/lov_nosom" $LOV_PATTERN_RAID0 1048576 - 3 >&2
	echo "ea_set -f $WORK/lov_nosom striped_nosom trusted.lov"

	mk_lov "$WORK/lov_pooled1" $LOV_PATTERN_RAID0 4194304 fast 5 >&2
	echo "ea_set -f $WORK/lov_pooled1 pooled1 trusted.lov"
	mk_som "$WORK/som_pooled1" $SOM_FL_LAZY 4096 8 >&2
	echo "ea_set -f $WORK/som_pooled1 pooled1 trusted.som"

	# HSM-released: no objects left, and the MDT holds the size (§4).
	mk_lov "$WORK/lov_hsmrel1" \
		$((LOV_PATTERN_RAID0 | LOV_PATTERN_F_RELEASED)) 1048576 - 1 >&2
	echo "ea_set -f $WORK/lov_hsmrel1 hsmrel1 trusted.lov"

	# PFL: a data-on-MDT first component, then one OST stripe.
	mk_lov_comp "$WORK/lov_comp1" 1048576 "$LOV_PATTERN_MDT:" \
		"$LOV_PATTERN_RAID0:9" >&2
	echo "ea_set -f $WORK/lov_comp1 comp1 trusted.lov"
	mk_som "$WORK/som_comp1" $SOM_FL_LAZY $((512 * 1024 * 1024)) \
		$((512 * 1024 * 1024 / 512)) >&2
	echo "ea_set -f $WORK/som_comp1 comp1 trusted.som"

	mk_linkea "$WORK/link_named1" report_2026.csv second_link.txt >&2
	echo "ea_set -f $WORK/link_named1 named1 trusted.link"

	# 60 stripes is 1472 bytes of LOV, which cannot fit a 1024-byte inode:
	# ext4 spills it to an external EA block, which is tier 2 by definition
	# and the only way to exercise that path without a real wide-striped fs.
	mk_lov "$WORK/lov_wide1" $LOV_PATTERN_RAID0 1048576 - \
		$(seq 0 59) >&2
	echo "ea_set -f $WORK/lov_wide1 widelov1 trusted.lov"

	mk_lmv "$WORK/lmv_dir1" 4 $LMV_HASH_FNV_1A_64 >&2
	echo "ea_set -f $WORK/lmv_dir1 stripedir1 trusted.lmv"
} > "$WORK/ea.debugfs" 2>/dev/null

debugfs -w -f "$WORK/ea.debugfs" "$IMG" >/dev/null 2>&1

# --- set projid and an old atime for filter tests --------------------------
{
	echo "sif proj1999 projid 1999"
	echo "sif oldatime atime 200001010000"
	# EXT4_IMMUTABLE_FL — the same bit STATX_ATTR_IMMUTABLE uses, which is
	# what lets --attrs compare i_flags directly (src/lfu_lustre.h).
	echo "sif immutable1 flags 0x10"
	# EXT4_ENCRYPT_FL.  A real encrypted file carries both this and
	# LMAI_ENCRYPT in its LMA; the record surfaces the latter as
	# +encrypted, while --attrs Encrypted reads the inode flag, which is
	# what statx reports and therefore what lfs find compares.
	echo "sif encrypted1 flags 0x800"
} > "$WORK/attr.debugfs"
debugfs -w -f "$WORK/attr.debugfs" "$IMG" >/dev/null 2>&1

echo "==> done: $IMG"
