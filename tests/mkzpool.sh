#!/bin/bash
# Build a synthetic Lustre-MDT-like ZFS dataset for lfind-zfs tests.
# Requires root (zpool create + trusted.* xattrs). File-backed vdev.
#
# NOT a real osd-zfs MDT: objects are created through the ZPL with
# hand-written trusted.lma xattrs, which exercises enumeration, SA reads,
# DXATTR unpacking and classification — but not osd-zfs's own object
# creation. The fidelity gap is recorded in design-zfs-scanner.md §10.
set -eu

POOL=${LFU_TEST_POOL:-lfutest}
DS=$POOL/mdt0
VDEV=${LFU_TEST_VDEV:-/var/tmp/lfu-zpool-test.img}

zpool destroy "$POOL" 2>/dev/null || true
rm -f "$VDEV"
truncate -s 1G "$VDEV"
# Created by the installed userland, so only features it knows are enabled —
# keeps the pool readable by the libzpool the scanner links against.
zpool create -o cachefile=/etc/zfs/zpool.cache "$POOL" "$VDEV"
zfs create -o xattr=sa -o dnodesize=auto "$DS"

python3 - "$POOL" <<'EOF'
import os, struct, sys
pool = sys.argv[1]
base = f"/{pool}/mdt0"

FID_SEQ_NORMAL   = 0x200000401
FID_SEQ_INTERNAL = 0x200000003          # reserved range below NORMAL
FID_SEQ_IDIF     = 0x100000000          # OST object by sequence
LMAC_NOT_IN_OI   = 0x4
LMAI_AGENT       = 0x2
BAD_INCOMPAT     = 0x80000000           # unknown incompat bit

def lma(compat, incompat, seq, oid, ver=0):
    return struct.pack("<IIQII", compat, incompat, seq, oid, ver)

def mk(path, content, xat=None):
    with open(path, "w") as f: f.write(content)
    if xat is not None:
        os.setxattr(path, "trusted.lma", xat)

# 60 ordinary visible files across 3 dirs
n = 0
for d in range(3):
    os.makedirs(f"{base}/d{d}", exist_ok=True)
    for i in range(20):
        mk(f"{base}/d{d}/f{i}", "x" * (i % 9),
           lma(0, 0, FID_SEQ_NORMAL, d * 100 + i))
        n += 1
# one large INCOMPRESSIBLE file so --blocks-gt has something to find
# (compression=on is the OpenZFS 2.2 default and doi_physical_blocks_512
#  is post-compression — matches stat() on ZFS, differs from ldiskfs)
with open(f"{base}/big", "wb") as f: f.write(os.urandom(262144))
os.setxattr(f"{base}/big", "trusted.lma", lma(0, 0, FID_SEQ_NORMAL, 9999))
n += 1
# a visible symlink with LMA
os.symlink("d0/f0", f"{base}/sym0")
os.setxattr(f"{base}/sym0", "trusted.lma",
            lma(0, 0, FID_SEQ_NORMAL, 8888), follow_symlinks=False)
n += 1
# classification exercises
mk(f"{base}/internal_seq",  "i", lma(0, 0, FID_SEQ_INTERNAL, 1))
mk(f"{base}/internal_flag", "i", lma(LMAC_NOT_IN_OI, 0, FID_SEQ_NORMAL, 7000))
mk(f"{base}/ost_obj",       "o", lma(0, 0, FID_SEQ_IDIF, 7001))
mk(f"{base}/agent",         "a", lma(0, LMAI_AGENT, FID_SEQ_NORMAL, 7002))
mk(f"{base}/bad_incompat",  "b", lma(0, BAD_INCOMPAT, FID_SEQ_NORMAL, 7003))
# an object with a non-LMA SA xattr only (DXATTR present, no trusted.lma)
mk(f"{base}/other_xattr",   "z")
os.setxattr(f"{base}/other_xattr", "trusted.somethingelse", b"hello")
# and one with no xattrs at all
mk(f"{base}/no_lma", "plain")

# --- tier-1 fixtures, the same bytes tests/mkimage.sh writes ----------------
# Everything here lands in the one SA_ZPL_DXATTR nvlist, which is why tier 1
# costs what tier 0 costs on this backend (docs/filter-levels.md §6).
SOM_FL_LAZY            = 0x4
LOV_MAGIC_V1           = 0x0BD10BD0
LOV_MAGIC_V3           = 0x0BD30BD0
LMV_MAGIC_V1           = 0x0CD20CD0
LOV_PATTERN_RAID0      = 0x1
LOV_PATTERN_F_RELEASED = 0x80000000
LINK_EA_MAGIC          = 0x11EAF1DF

def som(size, blocks, valid=SOM_FL_LAZY):
    return struct.pack("<4H2Q", valid, 0, 0, 0, size, blocks)

def lov(pattern, ssize, osts, pool=None):
    magic = LOV_MAGIC_V3 if pool else LOV_MAGIC_V1
    b = struct.pack("<II16sIHH", magic, pattern, b"\0" * 16, ssize,
                    len(osts), 0)
    if pool:
        b += pool.encode().ljust(16, b"\0")
    return b + b"".join(struct.pack("<16sII", b"\0" * 16, 0, o) for o in osts)

def lmv(count, hashtype):
    return struct.pack("<8IQ16s", LMV_MAGIC_V1, count, 0, hashtype,
                       0, 0, 0, 0, 0, b"")

def linkea(*names):
    recs = b""
    for nm in names:
        nb = nm.encode()
        reclen = 2 + 16 + len(nb)
        recs += bytes([(reclen >> 8) & 0xff, reclen & 0xff]) + b"\0" * 16 + nb
    # header in host order, exactly as linkea_init() writes it
    return struct.pack("=IIQII", LINK_EA_MAGIC, len(names),
                       24 + len(recs), 0, 0) + recs

# striped1: 2 GiB on the OSTs, a handful of blocks of its own -- the shape
# that makes --dev-blocks and --blocks different answers (§4.3).
mk(f"{base}/striped1", "s", lma(0, 0, FID_SEQ_NORMAL, 6001))
os.setxattr(f"{base}/striped1", "trusted.lov",
            lov(LOV_PATTERN_RAID0, 1 << 20, [3, 7]))
os.setxattr(f"{base}/striped1", "trusted.som", som(2 << 30, (2 << 30) // 512))
n += 1
# striped, never closed since SOM was enabled: the undecided case (§4.4)
mk(f"{base}/striped_nosom", "s", lma(0, 0, FID_SEQ_NORMAL, 6002))
os.setxattr(f"{base}/striped_nosom", "trusted.lov",
            lov(LOV_PATTERN_RAID0, 1 << 20, [3]))
n += 1
mk(f"{base}/pooled1", "p", lma(0, 0, FID_SEQ_NORMAL, 6003))
os.setxattr(f"{base}/pooled1", "trusted.lov",
            lov(LOV_PATTERN_RAID0, 4 << 20, [5], pool="fast"))
os.setxattr(f"{base}/pooled1", "trusted.som", som(4096, 8))
n += 1
mk(f"{base}/hsmrel1", "r", lma(0, 0, FID_SEQ_NORMAL, 6004))
os.setxattr(f"{base}/hsmrel1", "trusted.lov",
            lov(LOV_PATTERN_RAID0 | LOV_PATTERN_F_RELEASED, 1 << 20, [1]))
n += 1
mk(f"{base}/named1", "l", lma(0, 0, FID_SEQ_NORMAL, 6005))
os.setxattr(f"{base}/named1", "trusted.link",
            linkea("report_2026.csv", "second_link.txt"))
n += 1
os.makedirs(f"{base}/stripedir1", exist_ok=True)
os.setxattr(f"{base}/stripedir1", "trusted.lma",
            lma(0, 0, FID_SEQ_NORMAL, 6006))
os.setxattr(f"{base}/stripedir1", "trusted.lmv", lmv(4, 2))
n += 1

print(f"visible={n}")  # 68: 60 + big + symlink + 6 tier-1 fixtures
EOF

zpool sync "$POOL"
zfs snapshot "$DS@s1"
echo "rig ready: $DS@s1"
