#!/usr/bin/env python3
"""2026-09-20 fixes for the lreview of 68156 PS22 and 68095 PS22.

Eleven findings: the eight on 68156 (b6c43adc81) and the three on 68095
(eb773b585f), reported in docs/local/lreview-0918/markdown/.  Transforms
over each commit's tree, applied by ../r-0918/r0918drive.py with the
round-3 engine: a transform applies wherever its old text is present.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "r3-0913"))
import r3fix  # noqa: E402

MSG = r3fix.MSG
# the driver names commits c00..c25, bottom to top, so `since` speaks that
r3fix.ORDER = ["c%02d" % i for i in range(64)]
T = []


def t(tid, path, old, new, only=None, since=None, count_all=False):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=count_all))


API = "include/lustre/lustreapi.h"
DEV3 = "Documentation/man3/llapi_scan_device.3"
PFIND = "lustre/utils/liblustreapi_pfind.c"
DEV = "lustre/utils/liblustreapi_scan_device.c"
LDISK = "lustre/utils/libscan_ldiskfs.c"
BEH = "lustre/utils/lustreapi_scan_backend.h"
FIDH = "include/uapi/linux/lustre/lustre_fid.h"

# ============================================ 68156 item 1: the orphan class
t("orphan-enum", API,
  "\tLLAPI_SCAN_CLS_BAD = 5,\t\t/* LMA has an unknown incompat bit */\n"
  "\tLLAPI_SCAN_CLS_MAX = 6\n",
  "\tLLAPI_SCAN_CLS_BAD = 5,\t\t/* LMA has an unknown incompat bit */\n"
  "\t/*\n"
  "\t * in PENDING: an open-unlinked file, or a volatile one a migrate,\n"
  "\t * resync or HSM restore is using.  It keeps a link and a FID, so it\n"
  "\t * would otherwise read as visible, but no name reaches it.\n"
  "\t */\n"
  "\tLLAPI_SCAN_CLS_ORPHAN = 6,\n"
  "\tLLAPI_SCAN_CLS_MAX = 7\n")

t("orphan-classify", DEV,
  "\tif (fid_seq_is_idif(seq))\n"
  "\t\treturn LLAPI_SCAN_CLS_OST_OBJ;\n",
  "\tif (fid_seq_is_idif(seq))\n"
  "\t\treturn LLAPI_SCAN_CLS_OST_OBJ;\n"
  "\t/*\n"
  "\t * PENDING keeps a link to an open-unlinked file, so it has a normal\n"
  "\t * FID and would otherwise read as visible.  Last of the tests, so\n"
  "\t * only what would have been visible changes class.\n"
  "\t */\n"
  "\tif (lma->lma_incompat & LMAI_ORPHAN)\n"
  "\t\treturn LLAPI_SCAN_CLS_ORPHAN;\n")

t("orphan-man", DEV3,
  ".B LLAPI_SCAN_CLS_BAD\n"
  "its LMA sets an incompatible bit this library does not know, so what the\n"
  "object is cannot be decided. It is counted, and held back with the rest.\n"
  ".LP\n",
  ".B LLAPI_SCAN_CLS_BAD\n"
  "its LMA sets an incompatible bit this library does not know, so what the\n"
  "object is cannot be decided. It is counted, and held back with the rest.\n"
  ".TP\n"
  ".B LLAPI_SCAN_CLS_ORPHAN\n"
  "an open\\-unlinked file, or a volatile one a migrate, resync or HSM restore\n"
  "is using \\(em\n"
  ".B LMAI_ORPHAN\n"
  "in\n"
  ".IR lma_incompat ,\n"
  "which\n"
  ".BR mdd_mark_orphan_object ()\n"
  "sets. PENDING keeps a link to it, so it has a FID and would otherwise read\n"
  "as visible, but no name reaches it: it is gone when the MDT next mounts and\n"
  "clears PENDING.\n"
  ".LP\n")

# ============================================ 68156 item 2: no layout, no blocks
t("noreg-blocks", DEV,
  "\t\t/* nothing is striped out from under it */\n"
  "\t\trec->lfsr_stx.stx_size = obj->so_size;\n"
  "\t\trec->lfsr_stx.stx_blocks = obj->so_blocks;\n",
  "\t\t/* nothing is striped out from under it */\n"
  "\t\trec->lfsr_stx.stx_size = obj->so_size;\n"
  "\t\t/*\n"
  "\t\t * A regular file with no layout has no data blocks: the MDT\n"
  "\t\t * inode's own are its xattrs, which mdt_pack_attr2body()\n"
  "\t\t * does not report either.\n"
  "\t\t */\n"
  "\t\trec->lfsr_stx.stx_blocks = S_ISREG(obj->so_mode) ? 0 :\n"
  "\t\t\t\t\t   obj->so_blocks;\n")

# ============================================ 68156 item 3: the plugin's name
t("so-name", DEV,
  "\t * scan_ldiskfs.so out of step with this library is a real arrival --\n"
  "\t * and a symbol missing from it would be called through NULL.\n",
  "\t * scan_osd_ldiskfs.so out of step with this library is a real\n"
  "\t * arrival -- and a symbol missing from it would be called through\n"
  "\t * NULL.\n")

# ============================================ 68156 item 4: what ss_skipped holds
t("skipped-man", DEV3,
  "is normally zero. The exception is ldiskfs open-unlinked files still on the\n"
  "orphan list, as in a snapshot of a target in service or after a crash: they\n"
  "have no links and are counted in\n"
  ".IR ss_skipped .\n",
  "is normally zero. The exception is ldiskfs inodes left on the orphan list\n"
  "with no links at all, as in a snapshot of a target in service or after a\n"
  "crash: they are counted in\n"
  ".IR ss_skipped .\n"
  "Lustre's own open\\-unlinked files are not among them \\(em PENDING keeps a\n"
  "link to each, so they are read and classified\n"
  ".BR LLAPI_SCAN_CLS_ORPHAN .\n")

# ============================================ 68156 item 5: the option is --attrs
t("attrs-man", DEV3, ".B lfs find -attrs\n", ".B lfs find --attrs\n")

# ============================================ 68156 item 6: describe the field
t("field-ino", API,
  "/*\n"
  " * A scanner that reads a target's objects directly answers for these, and\n"
  " * one that walks a namespace does not: it is standing in the namespace and\n"
  " * has no need of them.\n"
  " */\n",
  "/*\n"
  " * The object as the target holds it: its id there, the parent and name its\n"
  " * linkea records, and its LMA.\n"
  " */\n")

t("field-class", API,
  " * A namespace walk only ever reaches namespace-visible objects.  A scanner\n"
  " * reading a target directly also finds the objects the filesystem keeps for\n"
  " * itself, and a consumer that acts on what it is given has to be able to\n"
  " * tell them apart.\n",
  " * Besides the objects a client can name, a target holds the ones the\n"
  " * filesystem keeps for itself, and a consumer that acts on what it is\n"
  " * given has to be able to tell them apart.\n")

t("field-path", API,
  " * The pointer fields carry their own answer: lfsr_path is NULL for a scanner\n"
  " * that has no namespace to walk, and lfsr_name is NULL when it could not\n"
  " * recover one.  A path is not a scan's to invent.\n",
  " * The pointer fields carry their own answer: lfsr_path is NULL where no\n"
  " * namespace was walked, and lfsr_name is NULL where no name was recovered.\n"
  " * A path is not a scan's to invent.\n")

t("field-lmv", API,
  "\t * The directory stripe, in the lmv_user_md form unless\n"
  "\t * LLAPI_SCAN_LMV_FOREIGN says otherwise: a device scan converts the\n"
  "\t * on-disk lmv_mds_md_v1 it reads, so the field means one thing\n"
  "\t * whichever scanner filled it.  A foreign LMV has no such form and\n"
  "\t * is delivered as the struct lmv_foreign_md it is, which is what\n"
  "\t * that bit is for.  A device scan does not carry the shard FIDs --\n"
  "\t * naming a stripe needs an MDT index, which is an FLD lookup it has\n"
  "\t * no client to make.\n"
  "\t *\n"
  "\t * So lum_objects[] is measured by lfsr_lmvsize and never by\n"
  "\t * lum_stripe_count: the count is the directory's real one either\n"
  "\t * way, but only a namespace scan is answered with the shards to\n"
  "\t * match it, and the two sizes differ by 24 bytes a stripe.\n",
  "\t * The directory stripe, in the lmv_user_md form unless\n"
  "\t * LLAPI_SCAN_LMV_FOREIGN says otherwise: a foreign LMV has no such\n"
  "\t * form and is delivered as the struct lmv_foreign_md it is, which\n"
  "\t * is what that bit is for.\n"
  "\t *\n"
  "\t * The shard FIDs may be absent, naming a stripe needing an MDT\n"
  "\t * index and so an FLD lookup, so lum_objects[] is measured by\n"
  "\t * lfsr_lmvsize and never by lum_stripe_count: the count is the\n"
  "\t * directory's real one either way, and the two sizes differ by 24\n"
  "\t * bytes a stripe.\n")

t("field-fromhere", API,
  "\t/* from here on, what a scan of a target's own objects answers for */\n",
  "\t/* from here on, the object as the target holds it */\n")

# ============================================ 68156 item 7: comments on the code
t("narr-bound", LDISK,
  "\t\t\t * Without the bound an unreadable inode just past\n"
  "\t\t\t * end_ino was consumed by this chunk and read again\n"
  "\t\t\t * by the chunk starting there, and ss_seen and\n"
  "\t\t\t * ss_skipped counted it twice.  Nothing was\n"
  "\t\t\t * delivered twice; it was the accounting that\n"
  "\t\t\t * overstated.\n",
  "\t\t\t * The bound matters here too: an unreadable inode\n"
  "\t\t\t * past end_ino belongs to the chunk starting\n"
  "\t\t\t * there, which reads it again, so counting it in\n"
  "\t\t\t * this one counts it twice.\n")

t("narr-lostfound", DEV,
  "\t\t * inode numbers -- so lost+found came out as [0xb:0x0:0x0],\n"
  "\t\t * which is FID_SEQ_RSVD and names something else entirely.\n"
  "\t\t * Below the IGIF range there is no IGIF, and the object is\n"
  "\t\t * left with the target's own id for it.\n",
  "\t\t * inode numbers: lost+found would be [0xb:0x0:0x0], which is\n"
  "\t\t * FID_SEQ_RSVD and names something else entirely.  Below the\n"
  "\t\t * IGIF range there is no IGIF, and the object is left with\n"
  "\t\t * the target's own id for it.\n")

t("narr-skipcount", DEV,
  "\t * after the pre-filter has run and its object is already in ss_seen;\n"
  "\t * counting it again inflated exactly the torn-read case these\n"
  "\t * counters exist to describe.\n",
  "\t * after the pre-filter has run and its object is already in ss_seen,\n"
  "\t * so counting it again would inflate exactly the torn-read case\n"
  "\t * these counters exist to describe.\n")

t("narr-padding", BEH,
  "\t * the scanner would over-claim for one of them.\n"
  "\t *\n"
  "\t * Carved from the padding, so every offset above is unchanged.\n"
  "\t */\n",
  "\t * the scanner would over-claim for one of them.\n"
  "\t */\n")

# ============================================ 68156 item 8: the original comment
t("fid-root", FIDH,
  " * the root FID will still be IGIF\n"
  " *\n"
  " * Here rather than in lustre_fid.h because it is only LU_ROOT_FID and\n"
  " * lu_fid_eq(), both of which are above, and userspace has the same question\n"
  " * to ask: a scan of a target has to tell the root from the rest of\n"
  " * FID_SEQ_ROOT.  unlikely() is not used, this header being compiled in\n"
  " * userspace too.\n"
  " */\n",
  " * the root FID will still be IGIF\n"
  " */\n")

# ============================================ 68095 item 1: %Li on a foreign dir
t("printf-Li", PFIND,
  "\t\tcase 'i':\t/* starting index */\n"
  "\t\t\t*wrote = snprintf(buffer, size, \"%d\",\n"
  "\t\t\t\t\t  lum->lum_stripe_offset);\n"
  "\t\t\tbreak;\n",
  "\t\tcase 'i':\t/* starting index */\n"
  "\t\t\t/*\n"
  "\t\t\t * A foreign LMV has no stripe offset: lfm_type is\n"
  "\t\t\t * at that offset, so the directory's own MDT index\n"
  "\t\t\t * is printed instead, from where the gather left\n"
  "\t\t\t * it.\n"
  "\t\t\t */\n"
  "\t\t\tif (lmv_is_foreign(lum->lum_magic)) {\n"
  "\t\t\t\tif (param->fp_file_mdt_index == OBD_NOT_FOUND)\n"
  "\t\t\t\t\tgoto format_done;\n"
  "\t\t\t\t*wrote = snprintf(buffer, size, \"%d\",\n"
  "\t\t\t\t\t\t  param->fp_file_mdt_index);\n"
  "\t\t\t\tbreak;\n"
  "\t\t\t}\n"
  "\t\t\t*wrote = snprintf(buffer, size, \"%d\",\n"
  "\t\t\t\t\t  lum->lum_stripe_offset);\n"
  "\t\t\tbreak;\n",
  since="c01")

# ============================================ 68095 item 2: the projid comments
t("projid-outer", PFIND,
  "\t\t * project id cannot be answered for such an object, so it\n"
  "\t\t * does not match; one that only prints it prints DEFAULT_PROJID.\n",
  "\t\t * project id cannot be answered for such an object, so\n"
  "\t\t * --projid N does not match; ! --projid N does, and one that\n"
  "\t\t * only prints it prints DEFAULT_PROJID.\n")

t("projid-inner", PFIND,
  "\t\t\t * made this disagree with -printf, which already\n"
  "\t\t\t * prints none for the same object.\n",
  "\t\t\t * made this disagree with -printf, which already\n"
  "\t\t\t * prints DEFAULT_PROJID for the same object.\n")

# ============================================ 68095 item 3: comments on the code
t("narr-walkfid", PFIND,
  "\t\t\t * A walk now descends a directory that is not on\n"
  "\t\t\t * Lustre -- cb_find_init() treats the stripe ioctl's\n"
  "\t\t\t * ENOTTY as \"no stripe\" rather than an error -- so\n"
  "\t\t\t * the objects under it reach here.  Having no FID is\n"
  "\t\t\t * what such an object is, not a failure to report:\n"
  "\t\t\t * the directive stays empty and nothing is said.\n",
  "\t\t\t * A walk descends a directory that is not on Lustre\n"
  "\t\t\t * -- cb_find_init() treats the stripe ioctl's ENOTTY\n"
  "\t\t\t * as \"no stripe\" rather than an error -- so the\n"
  "\t\t\t * objects under it reach here.  Having no FID is what\n"
  "\t\t\t * such an object is, not a failure to report: the\n"
  "\t\t\t * directive stays empty and nothing is said.\n")

t("narr-errno", PFIND,
  "\t\t * EIO from a flush -- sets errno of its own, and this errno\n"
  "\t\t * now picks a branch rather than only wording a message.\n",
  "\t\t * EIO from a flush -- sets errno of its own, and this errno\n"
  "\t\t * picks the branch below.\n")

t("narr-projid-walk", PFIND,
  "\t\t\t * that is not on Lustre answers ENOTTY.  A walk now\n"
  "\t\t\t * descends such a subtree, and having no project id\n"
  "\t\t\t * is what an object there is rather than a failure to\n"
  "\t\t\t * report -- as with the FID and the layout, which\n"
  "\t\t\t * this walk already keeps quiet about.\n",
  "\t\t\t * that is not on Lustre answers ENOTTY.  Having no\n"
  "\t\t\t * project id is what an object there is rather than a\n"
  "\t\t\t * failure to report, as with its FID and its layout.\n")

# the same sentence in its two spellings: before 68157's rename, and after
t("narr-reachable-old", PFIND,
  "\t\t * Reachable because -printf sets gather_all and this walk\n"
  "\t\t * now descends off Lustre: left as an error it exited\n"
  "\t\t * non-zero on the first symlink under the subtree, and on a\n"
  "\t\t * pre-v6.0 client on the first regular file.\n",
  "\t\t * Reachable because -printf sets gather_all: left as an\n"
  "\t\t * error, the walk would exit non-zero on the first symlink\n"
  "\t\t * under the subtree, and on a pre-v6.0 client on the first\n"
  "\t\t * regular file.\n")

t("narr-reachable-new", PFIND,
  "\t\t * Reachable because -printf sets gather_all: left as an\n"
  "\t\t * error, the walk exited non-zero on the first symlink under\n"
  "\t\t * the subtree, and on a pre-v6.0 client on the first file.\n",
  "\t\t * Reachable because -printf sets gather_all: left as an\n"
  "\t\t * error, the walk would exit non-zero on the first symlink\n"
  "\t\t * under the subtree, and on a pre-v6.0 client on the first\n"
  "\t\t * regular file.\n")


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
