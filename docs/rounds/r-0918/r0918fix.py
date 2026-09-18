#!/usr/bin/env python3
"""2026-09-18 fixes for the AI review of 68094 PS20, 68095 PS21, 68156 PS21.

Transforms over each commit's tree, applied by r0918drive.py with the
round-3 engine (docs/rounds/r3-0913/r3fix.py): a transform applies wherever
its old text is present.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "r3-0913"))
import r3fix  # noqa: E402

MSG = r3fix.MSG
T = []


def t(tid, path, old, new, only=None, since=None, count_all=False):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=count_all))


API = "include/lustre/lustreapi.h"
NS3 = "Documentation/man3/llapi_scan_namespace.3"
DEV3 = "Documentation/man3/llapi_scan_device.3"
SANITY = "lustre/tests/sanity.sh"
PFIND = "lustre/utils/liblustreapi_pfind.c"
SCAN = "lustre/utils/liblustreapi_scan.c"
INTH = "lustre/utils/lustreapi_internal.h"
DEV = "lustre/utils/liblustreapi_scan_device.c"
LDISK = "lustre/utils/libscan_ldiskfs.c"

# ------------------------------------------------ 68094 lustreapi.h:639
t("ac853bff", API,
  " * Valid only for the duration of the callback it is passed to.  lfsr_path,\n"
  " * lfsr_name and lfsr_lmm point into scanner-owned memory and must be copied by\n"
  " * a consumer that keeps them.\n",
  " * Valid only for the duration of the callback it is passed to.  lfsr_path,\n"
  " * lfsr_name, lfsr_lmm and lfsr_lmv point into scanner-owned memory and must\n"
  " * be copied by a consumer that keeps them.\n")

# ------------------------------------------------ 68094 man3:303
t("aea0225b", NS3,
  "set beside it when the buffer is a\n"
  ".B struct lmv_foreign_md\n"
  "rather than an\n",
  "set beside it when the buffer is a\n"
  ".B struct lmv_foreign_md\n"
  "(declared in\n"
  ".BR <linux/lustre/lustre_idl.h> )\n"
  "rather than an\n")

# ------------------------------------------------ 68094 man3:476
t("cb723540", NS3,
  "                if ((rec->lfsr_stx.stx_mask & STATX_MODE) &&\n",
  "                if ((rec->lfsr_stx.stx_mask & STATX_TYPE) &&\n")

# ------------------------------------------------ 68095 sanity.sh:10606
t("7bf450ef", SANITY,
  "\t# the walk descends into a subtree that is not on Lustre; --links\n"
  "\t# fetches each directory's LMV, which off Lustre answers ENOTTY\n"
  "\tlocal raw\n"
  "\n"
  "\traw=$($LFS find $dir -type f --links 1) ||\n"
  "\t\terror \"lfs find failed on $dir\"\n"
  "\tfound=$(wc -l <<< \"$raw\")\n"
  "\t(( found == 3 )) ||\n"
  "\t\terror \"lfs find found $found files under $dir, expected 3\"\n",
  "\t# the walk descends into a subtree that is not on Lustre, where each\n"
  "\t# object's stat and, for --links, each directory's LMV answer ENOTTY.\n"
  "\t# No -type: d_type would reject the directories before the LMV fetch.\n"
  "\tlocal raw\n"
  "\n"
  "\traw=$($LFS find $dir --links 1) ||\n"
  "\t\terror \"lfs find failed on $dir\"\n"
  "\tfound=$(wc -l <<< \"$raw\")\n"
  "\t# f1, f2, f3 and l1; every directory has more than one link\n"
  "\t(( found == 4 )) ||\n"
  "\t\terror \"lfs find found $found objects under $dir, expected 4\"\n")

# ------------------------------------------------ 68095 scan.c:292 rename
t("be5960c4-h1", INTH,
  "int scan_rec_gather_lmv(struct find_param *param, char *path, int d,\n"
  "\t\t\t__u64 want, bool *have_lmv);\n",
  "int scan_rec_gather_begin(struct find_param *param, char *path, int d,\n"
  "\t\t\t  __u64 want, bool *have_lmv);\n")
t("be5960c4-h2", INTH,
  "int scan_rec_gather_rest(struct find_param *param, char *path, int p,\n"
  "\t\t\t int d, int *fdp, __u64 want, bool have_lmv,\n"
  "\t\t\t struct llapi_scan_rec *rec);\n",
  "int scan_rec_gather_finish(struct find_param *param, char *path, int p,\n"
  "\t\t\t   int d, int *fdp, __u64 want, bool have_lmv,\n"
  "\t\t\t   struct llapi_scan_rec *rec);\n")
t("be5960c4-s1", SCAN,
  "int scan_rec_gather_lmv(struct find_param *param, char *path, int d,\n"
  "\t\t\t__u64 want, bool *have_lmv)\n",
  "int scan_rec_gather_begin(struct find_param *param, char *path, int d,\n"
  "\t\t\t  __u64 want, bool *have_lmv)\n")
t("be5960c4-s2", SCAN,
  "/* The second step of scan_rec_gather(), after scan_rec_gather_lmv(). */\n"
  "int scan_rec_gather_rest(struct find_param *param, char *path, int p,\n"
  "\t\t\t int d, int *fdp, __u64 want, bool have_lmv,\n"
  "\t\t\t struct llapi_scan_rec *rec)\n",
  "/* The second step of scan_rec_gather(), after scan_rec_gather_begin(). */\n"
  "int scan_rec_gather_finish(struct find_param *param, char *path, int p,\n"
  "\t\t\t   int d, int *fdp, __u64 want, bool have_lmv,\n"
  "\t\t\t   struct llapi_scan_rec *rec)\n")
t("be5960c4-s3", SCAN,
  "\trc = scan_rec_gather_lmv(param, path, d, want, &have_lmv);\n",
  "\trc = scan_rec_gather_begin(param, path, d, want, &have_lmv);\n")
t("be5960c4-s4", SCAN,
  "\treturn scan_rec_gather_rest(param, path, p, d, fdp, want, have_lmv,\n"
  "\t\t\t\t    rec);\n",
  "\treturn scan_rec_gather_finish(param, path, p, d, fdp, want, have_lmv,\n"
  "\t\t\t\t      rec);\n")
t("be5960c4-p1", PFIND,
  "\t\tret = scan_rec_gather_lmv(param, path, d, want, &have_lmv);\n",
  "\t\tret = scan_rec_gather_begin(param, path, d, want, &have_lmv);\n")
t("be5960c4-p2", PFIND,
  "\t\t\tret = scan_rec_gather_rest(param, path, p, d, &fd, want,\n"
  "\t\t\t\t\t\t   have_lmv, &rec);\n",
  "\t\t\tret = scan_rec_gather_finish(param, path, p, d, &fd,\n"
  "\t\t\t\t\t\t     want, have_lmv, &rec);\n")
t("be5960c4-msg", MSG,
  "  calls its two steps itself, scan_rec_gather_lmv() and\n"
  "  scan_rec_gather_rest(), so",
  "  calls its two steps itself, scan_rec_gather_begin() and\n"
  "  scan_rec_gather_finish(), so")

# ------------------------------------------------ 68156 lustreapi.h:673
t("cb09f4cc", API,
  "\tLLAPI_SCAN_CLS_BAD = 5,\t\t/* unreadable or unsupported */\n",
  "\tLLAPI_SCAN_CLS_BAD = 5,\t\t/* LMA has an unknown incompat bit */\n")

# ------------------------------------------------ 68156 scan_device.c:400
t("5aeb39c8-fn", DEV,
  "/*\n"
  " * Size and blocks.  The object's own size is the file's only when the file\n"
  " * has no layout; trusted.som answers otherwise, and answers lazily, which is\n"
  " * what LLAPI_SCAN_LAZY_SIZE already means.\n"
  " */\n"
  "static void scan_size(",
  "/*\n"
  " * Whether HSM has released the file, decided as mdt_hsm_is_released()\n"
  " * does: every component released.  The bytes are raw from the target.\n"
  " */\n"
  "static bool scan_lov_released(const void *buf, size_t len)\n"
  "{\n"
  "\tconst struct lov_comp_md_v1 *comp = buf;\n"
  "\tconst struct lov_user_md_v1 *v1 = buf;\n"
  "\t__u32 magic;\n"
  "\t__u16 count;\n"
  "\t__u16 i;\n"
  "\n"
  "\tif (len < sizeof(*v1))\n"
  "\t\treturn false;\n"
  "\n"
  "\tmagic = __le32_to_cpu(v1->lmm_magic);\n"
  "\tif (magic == LOV_MAGIC_V1 || magic == LOV_MAGIC_V3)\n"
  "\t\treturn __le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED;\n"
  "\tif (magic != LOV_MAGIC_COMP_V1 || len < sizeof(*comp))\n"
  "\t\treturn false;\n"
  "\n"
  "\tcount = __le16_to_cpu(comp->lcm_entry_count);\n"
  "\tif (len < sizeof(*comp) + count * sizeof(comp->lcm_entries[0]))\n"
  "\t\treturn false;\n"
  "\tfor (i = 0; i < count; i++) {\n"
  "\t\t__u32 off = __le32_to_cpu(comp->lcm_entries[i].lcme_offset);\n"
  "\n"
  "\t\tif (off > len - sizeof(*v1))\n"
  "\t\t\treturn false;\n"
  "\t\tv1 = (const struct lov_user_md_v1 *)((const char *)buf + off);\n"
  "\t\tif (!(__le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED))\n"
  "\t\t\treturn false;\n"
  "\t}\n"
  "\treturn true;\n"
  "}\n"
  "\n"
  "/*\n"
  " * Size and blocks.  The object's own size is the file's only when the file\n"
  " * has no layout, or HSM has released it; trusted.som answers otherwise, and\n"
  " * answers lazily, which is what LLAPI_SCAN_LAZY_SIZE already means.\n"
  " */\n"
  "static void scan_size(")
t("5aeb39c8-decl", DEV,
  "\t\t      struct llapi_scan_rec *rec)\n"
  "{\n"
  "\tconst struct lustre_som_attrs *som;\n"
  "\tsize_t len = 0;\n"
  "\t__u16 valid;\n",
  "\t\t      struct llapi_scan_rec *rec)\n"
  "{\n"
  "\tconst struct lustre_som_attrs *som;\n"
  "\tconst void *lov;\n"
  "\tsize_t len = 0;\n"
  "\t__u16 valid;\n")
t("5aeb39c8-body", DEV,
  "\t\trec->lfsr_stx.stx_mask |= STATX_SIZE | STATX_BLOCKS;\n"
  "\t\treturn;\n"
  "\t}\n"
  "\n"
  "\tsom = scan_xattr(obj, LLAPI_SCAN_XA_SOM, &len);\n",
  "\t\trec->lfsr_stx.stx_mask |= STATX_SIZE | STATX_BLOCKS;\n"
  "\t\treturn;\n"
  "\t}\n"
  "\n"
  "\t/* released: the MDT inode holds the size; one block, as for a client */\n"
  "\tlov = scan_xattr(obj, LLAPI_SCAN_XA_LOV, &len);\n"
  "\tif (lov != NULL && scan_lov_released(lov, len)) {\n"
  "\t\trec->lfsr_stx.stx_size = obj->so_size;\n"
  "\t\trec->lfsr_stx.stx_blocks = obj->so_size == 0 ? 0 : 1;\n"
  "\t\trec->lfsr_stx.stx_mask |= STATX_SIZE | STATX_BLOCKS;\n"
  "\t\treturn;\n"
  "\t}\n"
  "\n"
  "\tsom = scan_xattr(obj, LLAPI_SCAN_XA_SOM, &len);\n")
t("5aeb39c8-man", DEV3,
  "the object's size is exactly what that OST holds \\(em and a regular file\n"
  "carrying no layout at all.\n",
  "the object's size is exactly what that OST holds \\(em and a regular file\n"
  "carrying no layout at all. So is a file that HSM has released: its data is\n"
  "in the archive, and the MDT keeps its size in the inode and reports one\n"
  "block for it, as a client sees it.\n")

# ------------------------------------------------ 68156 libscan_ldiskfs.c:579
t("8be61d7b", LDISK,
  "\t\t\t * The same two questions the readable path below\n"
  "\t\t\t * asks, and for the same reasons: whose chunk this\n"
  "\t\t\t * inode is, and whether it is an object at all.\n"
  "\t\t\t * ext2fs_get_next_inode_full() assigns *ino before\n"
  "\t\t\t * it returns any of these three, so both can be\n"
  "\t\t\t * asked here -- unlike the errors above, which\n"
  "\t\t\t * leave it untouched.\n",
  "\t\t\t * The same questions the readable path below asks,\n"
  "\t\t\t * and for the same reasons: whose chunk this inode\n"
  "\t\t\t * is, whether it is an object at all, and whether\n"
  "\t\t\t * the bitmap has it.  The bitmap is in another\n"
  "\t\t\t * block, read at open, so it is still good here.\n"
  "\t\t\t * ext2fs_get_next_inode_full() assigns *ino before\n"
  "\t\t\t * it returns any of these three, so all can be\n"
  "\t\t\t * asked here -- unlike the errors above, which\n"
  "\t\t\t * leave it untouched.\n")
t("8be61d7b-code", LDISK,
  "\t\t\tif (ino < EXT2_FIRST_INODE(fs->super))\n"
  "\t\t\t\tcontinue;\n"
  "\t\t\tsink->ss_skip(sink->ss_ctx, LLAPI_SCAN_SKIP_IO);\n",
  "\t\t\tif (ino < EXT2_FIRST_INODE(fs->super))\n"
  "\t\t\t\tcontinue;\n"
  "\t\t\tif (!ext2fs_test_inode_bitmap2(t->st_fs->inode_map,\n"
  "\t\t\t\t\t\t       ino))\n"
  "\t\t\t\tcontinue;\n"
  "\t\t\tsink->ss_skip(sink->ss_ctx, LLAPI_SCAN_SKIP_IO);\n")

# ------------------------------------------------ messages (plain English)
t("msg-56El", MSG,
  "sanity 56El mounts a tmpfs under the Lustre mount. It checks that the\n"
  "walk finds the files below it, and that -printf %LF and %Lc print\n"
  "nothing on stderr for them.",
  "sanity 56El mounts a tmpfs under the Lustre mount. It checks that the\n"
  "walk finds the objects below it with --links, so that each directory\n"
  "there has its LMV fetched, and that -printf %LF and %Lc print\n"
  "nothing on stderr for them.")
t("msg-released", MSG,
  "- LLAPI_SCAN_LMV_FOREIGN asked for alone also reads the LMV.\n",
  "- LLAPI_SCAN_LMV_FOREIGN asked for alone also reads the LMV.\n"
  "- A file that HSM has released gets its size from the MDT inode, and\n"
  "  one block, as a client sees it. Its old SOM is not used.\n")
t("msg-bitmap", MSG,
  "- An inode that cannot be read is counted once, by the chunk that owns\n"
  "  it.\n",
  "- An inode that cannot be read is counted once, by the chunk that owns\n"
  "  it, and only if the inode bitmap says it is in use.\n")


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
