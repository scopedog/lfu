#!/usr/bin/env python3
"""09-25 AI PS27 fixes, as one idempotent transform of a tree.

Applies whatever of itself the tree has anchors for, skips the rest.
Usage: xform.py <tree>   -- prints applied/skipped counts.
"""
import os, re, sys

T = sys.argv[1]
applied = skipped = 0


def edit(path, old, new, once=True):
    """replace old by new; skip if new already present or old absent"""
    global applied, skipped
    p = os.path.join(T, path)
    if not os.path.exists(p):
        skipped += 1
        return
    s = open(p).read()
    if old not in s or (new and once and new in s):
        skipped += 1
        return
    if once and s.count(old) != 1:
        sys.exit(f"ambiguous anchor in {path}: {old[:60]!r}")
    s = s.replace(old, new)
    open(p, "w").write(s)
    applied += 1


# ---- item 1: rdev + blksize on a device scan ------------------------------
edit("lustre/utils/lustreapi_scan_backend.h",
     "\t__u32\tso_gen;\n",
     "\t__u32\tso_gen;\n"
     "\t__u32\tso_rdev;\t\t/* la_rdev of a device node, as the OSD has it */\n")

edit("lustre/utils/libscan_ldiskfs.c",
     "\tobj->so_gen = inode->i_generation;\n",
     "\tobj->so_gen = inode->i_generation;\n"
     "\t/* as ext4_iget() reads i_rdev, which osd-ldiskfs reports as la_rdev */\n"
     "\tif (LINUX_S_ISCHR(inode->i_mode) || LINUX_S_ISBLK(inode->i_mode)) {\n"
     "\t\t__u32 old = inode->i_block[0];\n"
     "\t\t__u32 new = inode->i_block[1];\n"
     "\n"
     "\t\tif (old != 0)\n"
     "\t\t\tobj->so_rdev = (((old >> 8) & 0xff) << 20) | (old & 0xff);\n"
     "\t\telse\n"
     "\t\t\tobj->so_rdev = (((new & 0xfff00) >> 8) << 20) |\n"
     "\t\t\t\t       (new & 0xff) | ((new >> 12) & 0xfff00);\n"
     "\t}\n")

edit("lustre/utils/liblustreapi_scan_device.c",
     "\trec->lfsr_stx.stx_gid = obj->so_gid;\n",
     "\trec->lfsr_stx.stx_gid = obj->so_gid;\n"
     "\t/*\n"
     "\t * la_rdev holds the client's old_encode_dev() value; decode it as\n"
     "\t * ll_update_inode() does, so this is what stat(2) shows.\n"
     "\t */\n"
     "\tif (S_ISCHR(obj->so_mode) || S_ISBLK(obj->so_mode)) {\n"
     "\t\trec->lfsr_stx.stx_rdev_major = (obj->so_rdev >> 8) & 0xff;\n"
     "\t\trec->lfsr_stx.stx_rdev_minor = obj->so_rdev & 0xff;\n"
     "\t}\n"
     "\trec->lfsr_stx.stx_blksize = getpagesize();\t/* as ll_dir_ioctl() */\n")

edit("lustre/utils/libscan_zfs.c",
     "\tif (scan_zfs_sa_get_u64(hdl, a[ZPL_SIZE], &v) == 0)\n",
     "\t/* osd-zfs keeps la_rdev in ZPL_RDEV as it was given */\n"
     "\tif ((S_ISCHR(obj.so_mode) || S_ISBLK(obj.so_mode)) &&\n"
     "\t    scan_zfs_sa_get_u64(hdl, a[ZPL_RDEV], &v) == 0)\n"
     "\t\tobj.so_rdev = (__u32)v;\n"
     "\tif (scan_zfs_sa_get_u64(hdl, a[ZPL_SIZE], &v) == 0)\n")

edit("Documentation/man3/llapi_scan_device.3",
     "on \\(em the default \\(em is most of them.\n.LP\n",
     "on \\(em the default \\(em is most of them.\n"
     ".LP\n"
     "For a character or block device,\n"
     ".I lfsr_stx.stx_rdev_major\n"
     "and\n"
     ".I lfsr_stx.stx_rdev_minor\n"
     "are the device number that\n"
     ".BR stat (2)\n"
     "shows on a client.\n"
     "statx has no mask bit for them.\n"
     ".I lfsr_stx.stx_blksize\n"
     "is the page size, as a namespace scan reports it.\n"
     ".LP\n")

# ---- item 3: fc_projid / fc_have_projid read from the record ---------------
PF = "lustre/utils/liblustreapi_pfind.c"
edit(PF, "\t__u32\t\t\t fc_projid;\t/* only with fc_have_projid */\n", "")
edit(PF, "\tbool\t\t\t fc_have_projid;\n", "")
edit(PF,
     "\tif (fc->fc_have_projid) {\n\t\t*projid = fc->fc_projid;\n",
     "\tif (fc->fc_rec->lfsr_valid & LLAPI_SCAN_PROJID) {\n"
     "\t\t*projid = fc->fc_rec->lfsr_projid;\n")
edit(PF,
     "\t    (param->fp_format_printf_str != NULL && fc->fc_have_projid)) {\n",
     "\t    (param->fp_format_printf_str != NULL &&\n"
     "\t     (fc->fc_rec->lfsr_valid & LLAPI_SCAN_PROJID))) {\n")
# the three scan callbacks' copies
p = os.path.join(T, PF)
if os.path.exists(p):
    s = open(p).read()
    pat = ("\tfc.fc_have_projid = !!(rec->lfsr_valid & LLAPI_SCAN_PROJID);\n"
           "\tfc.fc_projid = rec->lfsr_projid;\n")
    n = s.count(pat)
    if n:
        open(p, "w").write(s.replace(pat, ""))
        applied += n
    else:
        skipped += 1

print(f"applied={applied} skipped={skipped}")
