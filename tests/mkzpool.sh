#!/bin/bash
# Build a synthetic Lustre-MDT-like ZFS dataset for lfu-scan-zfs tests.
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
print(f"visible={n}")  # 62: 60 + big + symlink
EOF

zpool sync "$POOL"
zfs snapshot "$DS@s1"
echo "rig ready: $DS@s1"
