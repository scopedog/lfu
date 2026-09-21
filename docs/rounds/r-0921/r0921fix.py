#!/usr/bin/env python3
"""2026-09-21 fixes for the Gerrit AI round on 68094 PS21, 68095 PS22 and
68156 PS22.

Five findings taken (one declined, see notes.md): the attrs gate on 68094,
the `! --foreign` getattr on 68095, and .gitignore plus the striped-directory
size on 68156.  Transforms over each commit's tree, applied by
../r-0918/r0918drive.py with the round-3 engine: a transform applies wherever
its old text is present.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "r3-0913"))
import r3fix  # noqa: E402

MSG = r3fix.MSG
# the driver names commits c00..c25, bottom to top, so `only` speaks that
r3fix.ORDER = ["c%02d" % i for i in range(64)]
T = []


def t(tid, path, old, new, only=None, since=None, count_all=False):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=count_all))


API = "include/lustre/lustreapi.h"
NS3 = "Documentation/man3/llapi_scan_namespace.3"
DEV3 = "Documentation/man3/llapi_scan_device.3"
SCAN = "lustre/utils/liblustreapi_scan.c"
PFIND = "lustre/utils/liblustreapi_pfind.c"
DEV = "lustre/utils/liblustreapi_scan_device.c"
IGN = "lustre/tests/.gitignore"

# the pre-split trees: cb_find_init() still holds its own decider
PRESPLIT = {"c01", "c02"}

# ===================================== 68094: what says the attrs were answered
t("attrs-gate", SCAN,
  "\t/*\n"
  "\t * stx_attributes has no bit of its own in stx_mask; what says the\n"
  "\t * flags are meaningful is the server declaring which it supports.\n"
  "\t * Masked down to that declaration, because the MDT ORs the raw inode\n"
  "\t * flags in and only the bits it names are STATX_ATTR_* values --\n"
  "\t * FS_INDEX_FL would otherwise read as STATX_ATTR_AUTOMOUNT.\n"
  "\t */\n"
  "\tif (rec->lfsr_stx.stx_attributes_mask != 0) {\n",
  "\t/*\n"
  "\t * stx_attributes has no bit of its own in stx_mask, so what says the\n"
  "\t * flags were answered is OBD_MD_FLFLAGS: mdt_pack_attr2body() sets\n"
  "\t * it only for LA_FLAGS, and ll_dir_ioctl() reads mbo_flags only\n"
  "\t * under it.  stx_attributes_mask is not that answer -- llite fills\n"
  "\t * it with a build-time constant, the STATX_ATTR_* bits the client\n"
  "\t * can represent -- so gating on it would set this bit for every\n"
  "\t * object whether or not the MDT reported flags at all.\n"
  "\t *\n"
  "\t * Masked down to that declaration all the same, because the MDT ORs\n"
  "\t * the raw inode flags in and only the bits it names are STATX_ATTR_*\n"
  "\t * values -- FS_INDEX_FL would otherwise read as STATX_ATTR_AUTOMOUNT.\n"
  "\t */\n"
  "\tif (flags & OBD_MD_FLFLAGS) {\n")

t("attrs-man", NS3,
  ".B LLAPI_SCAN_ATTRS\n"
  ".IR lfsr_stx.stx_attributes ,\n"
  "the\n"
  ".B STATX_ATTR_*\n"
  "bits the server declared it supports in\n"
  ".IR lfsr_stx.stx_attributes_mask ;\n"
  "flags outside that declaration are masked off rather than reported. This bit\n"
  "is in\n"
  ".I lfsr_valid\n"
  "because statx has no mask bit of its own for\n"
  ".IR stx_attributes .\n",
  ".B LLAPI_SCAN_ATTRS\n"
  ".IR lfsr_stx.stx_attributes ,\n"
  "set when the object's flags were answered \\(em\n"
  ".B OBD_MD_FLFLAGS\n"
  "in the MDT's reply, which it sets only when it filled them. The value is\n"
  "masked down to the\n"
  ".B STATX_ATTR_*\n"
  "bits named in\n"
  ".IR lfsr_stx.stx_attributes_mask ,\n"
  "which is the scanner's own declaration of what it can represent; flags\n"
  "outside it are masked off rather than reported. This bit is in\n"
  ".I lfsr_valid\n"
  "because statx has no mask bit of its own for\n"
  ".IR stx_attributes .\n")

# ============================== 68095: `! --foreign` costs no getattr again
HELPER = (
  "/*\n"
  " * `! --foreign` on a directory with no stripe of its own: accepted on the\n"
  " * LMV alone.  Nothing between here and the print reads what the getattr\n"
  " * fetches, so it is not asked for -- as it was not before this became a\n"
  " * record.  -printf is the exception: those attributes are what it prints.\n"
  " */\n"
  "static bool find_foreign_accepts(const struct find_param *param,\n"
  "\t\t\t\t bool have_lmv, bool gather_all)\n"
  "{\n"
  "\treturn param->fp_get_lmv && !have_lmv && !gather_all &&\n"
  "\t       param->fp_check_foreign && param->fp_exclude_foreign;\n"
  "}\n"
  "\n")

ANCHOR = (
  "/*\n"
  " * The checks that need only the directory's LMV.  Run before the stat RPC,\n"
  " * so a directory they reject costs no more than the LMV fetch.\n"
  " *\n"
  " * Return: true if the object is rejected.\n"
  " */\n")

t("foreign-helper", PFIND, ANCHOR, HELPER + ANCHOR, since="c01")

GATHER = (
  "\t\t/* the LMV first: its checks can reject before the stat RPC */\n"
  "\t\tret = scan_rec_gather_begin(param, path, d, want, &have_lmv);\n"
  "\t\tif (ret == 0 && find_lmv_rejects(param, have_lmv))\n"
  "\t\t\tgoto decided;\n")

t("foreign-early-95", PFIND, GATHER,
  GATHER +
  "\t\tif (ret == 0 &&\n"
  "\t\t    find_foreign_accepts(param, have_lmv, gather_all))\n"
  "\t\t\tgoto print;\n", only=PRESPLIT)

t("foreign-early-157", PFIND, GATHER,
  GATHER +
  "\t\tif (ret == 0 &&\n"
  "\t\t    find_foreign_accepts(param, have_lmv, gather_all))\n"
  "\t\t\tgoto decide;\n", since="c03")

t("foreign-label-157", PFIND,
  "\tfc.fc_rec = &rec;\n"
  "\tfc.fc_path = path;\n",
  "decide:\n"
  "\tfc.fc_rec = &rec;\n"
  "\tfc.fc_path = path;\n", since="c03")

# ============================================ 68156: the test binary is ignored
t("gitignore", IGN, "/llapi_scan_test\n",
  "/llapi_scan_test\n/llapi_scan_device_test\n", since="c02")

# =========================== 68156: a striped directory's size is not its own
t("striped-size-want", DEV,
  "\tif (want & (LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS |\n"
  "\t\t    LLAPI_SCAN_LAZY_SIZE | LLAPI_SCAN_LAZY_BLOCKS))\n"
  "\t\txa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LOV) |\n"
  "\t\t      LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_SOM);\n",
  "\t/*\n"
  "\t * trusted.lmv with it: a striped directory's own size is not the\n"
  "\t * directory's, and scan_size() has no other way to tell one.\n"
  "\t */\n"
  "\tif (want & (LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS |\n"
  "\t\t    LLAPI_SCAN_LAZY_SIZE | LLAPI_SCAN_LAZY_BLOCKS))\n"
  "\t\txa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LOV) |\n"
  "\t\t      LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_SOM) |\n"
  "\t\t      LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMV);\n", since="c02")

GATE = (
  "\tif (!(want & (LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS |\n"
  "\t\t      LLAPI_SCAN_LAZY_SIZE | LLAPI_SCAN_LAZY_BLOCKS)))\n"
  "\t\treturn;\n")

t("striped-size", DEV, GATE,
  GATE +
  "\n"
  "\t/*\n"
  "\t * A striped directory's size and blocks are aggregated by the client\n"
  "\t * across its shards, so the master object's own are not the\n"
  "\t * directory's: ll_dir_ioctl() drops STATX_SIZE and STATX_BLOCKS for\n"
  "\t * one, and a scan of a target, which holds only the master, answers\n"
  "\t * \"not known\" as well rather than a number of its own.\n"
  "\t */\n"
  "\tif (S_ISDIR(obj->so_mode) && scan_lmv_is_striped(obj))\n"
  "\t\treturn;\n", since="c02")

t("striped-helper", DEV,
  "/*\n"
  " * The directory stripe, converted to the form the record declares.\n",
  "/*\n"
  " * The master object of a striped directory: trusted.lmv holding an\n"
  " * lmv_mds_md_v1, which is what lmv_dir_striped() tests on the client side.\n"
  " * A shard's own LMV_MAGIC_STRIPE and a foreign LMV are neither.\n"
  " */\n"
  "static bool scan_lmv_is_striped(const struct llapi_scan_obj *obj)\n"
  "{\n"
  "\tsize_t len = 0;\n"
  "\t__u32 magic;\n"
  "\tconst void *lmv;\n"
  "\n"
  "\tlmv = scan_xattr(obj, LLAPI_SCAN_XA_LMV, &len);\n"
  "\tif (lmv == NULL || len < sizeof(magic))\n"
  "\t\treturn false;\n"
  "\n"
  "\tmemcpy(&magic, lmv, sizeof(magic));\n"
  "\n"
  "\treturn __le32_to_cpu(magic) == LMV_MAGIC_V1;\n"
  "}\n"
  "\n"
  "/*\n"
  " * The directory stripe, converted to the form the record declares.\n",
  since="c02")

MAN_HSM = (
  "block for it, as a client sees it.\n")

t("striped-man", DEV3, MAN_HSM,
  MAN_HSM +
  "A striped directory is the exception: the client aggregates its size and\n"
  "blocks across the shards, so the master object a target holds answers for\n"
  "neither, and both bits are left clear \\(em as\n"
  ".BR ll_dir_ioctl ()\n"
  "leaves them for a walk.\n", since="c02")


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
