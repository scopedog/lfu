#!/usr/bin/env python3
"""Artem Blagodarenko's fix, TLC commit ae5a21241a, folded into the stack.

Three wrong answers from a device scan of an MDT, reported on 68156 PS25
and 68159 PS22 (2026-09-23): the MDT's own files classified as visible,
a Data-on-MDT file with no size, and lfs find deciding -size on that
missing size as 0.  His code and man-page text, except where our stack has
moved past his base:

- the "has a link" test is a helper, scan_has_link().  From c22 it tests
  presence, not bytes: the kernel ring carries a link too big for it as
  presence only (LFU_REC_LINK_BIG), and an object whose xattr read was
  partial is not demoted, since not read is not absent;
- size_elsewhere is declared at the top of find_decide(), not mid-block.

c02 (68156) takes the classification and the DoM size, c05 (68159) the
undecided size; both commit messages credit him and carry his sign-off.
See notes.md, "Artem 3-6".
"""

DEV = "lustre/utils/liblustreapi_scan_device.c"
PFIND = "lustre/utils/liblustreapi_pfind.c"
DEV3 = "Documentation/man3/llapi_scan_device.3"

# -- c02: always read trusted.link --------------------------------------
WANT_CMT_OLD = """ * The xattrs a demand mask implies.  trusted.lma is always read: an object
 * without it has no FID and no class.  A size needs two, trusted.lov to say
 * whether the object's own size is the file's and trusted.som to answer when
 * it is not.
 */
static __u32 scan_want_xattr(__u64 want)
{
\t__u32 xa = LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMA);
"""
WANT_CMT_NEW = """ * The xattrs a demand mask implies.  trusted.lma and trusted.link are always
 * read: an object without an LMA has no FID and no class, and on an MDT one
 * with a namespace FID but no link is the target's own and not a file's --
 * see scan_classify().  A size needs two, trusted.lov to say whether the
 * object's own size is the file's and trusted.som to answer when it is not.
 */
static __u32 scan_want_xattr(__u64 want)
{
\t__u32 xa = LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMA) |
\t\t   LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LINK);
"""
WANT_LINK_OLD = """\tif (want & (LLAPI_SCAN_LINKEA | LLAPI_SCAN_PARENT))
\t\txa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LINK);
"""
WANT_LINK_NEW = ""

# -- c02: scan_has_link(), bytes; c22: presence ---------------------------
HASLINK_ANCHOR = """\t*len = obj->so_xattr[x].sv_len;
\treturn obj->so_xattr[x].sv_buf;
}
"""
HASLINK_C02 = HASLINK_ANCHOR + """
/* Whether the object has a trusted.link, as every name in the namespace does */
static bool scan_has_link(const struct llapi_scan_obj *obj)
{
\tsize_t len;

\treturn scan_xattr(obj, LLAPI_SCAN_XA_LINK, &len) != NULL;
}
"""
HASLINK_BODY_C02 = """\tsize_t len;

\treturn scan_xattr(obj, LLAPI_SCAN_XA_LINK, &len) != NULL;
}
"""
HASLINK_BODY_C22 = """\t/* not read is not absent: an object read in part keeps its class */
\tif (obj->so_valid & LLAPI_SCAN_SO_XA_PARTIAL)
\t\treturn true;
\t/* presence: the ring carries a link too big for it as presence only */
\treturn obj->so_xa_present & LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LINK);
}
"""

# -- c02: the classification ------------------------------------------------
CLS_HDR_OLD = """ * without an LMA: reconstructing one is LFSCK's job.
 */
static enum llapi_scan_class scan_classify(const struct lustre_mdt_attrs *lma,
\t\t\t\t\t   bool have_lma)
"""
CLS_HDR_NEW = """ * without an LMA: reconstructing one is LFSCK's job.
 *
 * fid_is_namespace_visible() goes by the FID alone, which is not enough on
 * an MDT: the target's own files outside ROOT -- CONFIGS/mountdata with an
 * IGIF, the update logs with a normal FID -- pass it.  What they lack is a
 * name in the namespace, so an MDT object with such a FID and no trusted.link
 * is the target's own.  So is a file from before linkEA (2.4) that LFSCK has
 * not given one yet: it is reachable, but nothing on the target says so.
 */
static enum llapi_scan_class scan_classify(const struct lustre_mdt_attrs *lma,
\t\t\t\t\t   bool have_lma, bool mdt,
\t\t\t\t\t   bool have_link)
"""
CLS_BODY_OLD = """\tif (fid_seq_is_norm(seq) || fid_seq_is_igif(seq) ||
\t    fid_is_root(&lma->lma_self_fid) ||
\t    fid_seq_is_dot(seq))
\t\treturn LLAPI_SCAN_CLS_VISIBLE;
"""
CLS_BODY_NEW = """\tif (fid_is_root(&lma->lma_self_fid) || fid_seq_is_dot(seq))
\t\treturn LLAPI_SCAN_CLS_VISIBLE;
\tif (fid_seq_is_norm(seq) || fid_seq_is_igif(seq))
\t\treturn mdt && !have_link ? LLAPI_SCAN_CLS_INTERNAL :
\t\t\t\t\t   LLAPI_SCAN_CLS_VISIBLE;
"""
CLS_CALL_OLD = "\tcls = scan_classify(&lma, have_lma);\n"
CLS_CALL_NEW = """\tcls = scan_classify(&lma, have_lma,
\t\t\t    dev->sd_tgt_info.tt_flags & LLAPI_SCAN_TGT_MDT,
\t\t\t    scan_has_link(obj));
"""
LINKEA_OLD = "\tscan_linkea(obj, w->sw_name, sizeof(w->sw_name), &rec);\n"
LINKEA_NEW = """\tif (dev->sd_want & (LLAPI_SCAN_LINKEA | LLAPI_SCAN_PARENT))
\t\tscan_linkea(obj, w->sw_name, sizeof(w->sw_name), &rec);
"""

# -- c02: DoM size ------------------------------------------------------------
DOMFN_OLD = """\t\tif (!(__le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED))
\t\t\treturn false;
\t}
\treturn true;
}

/*
 * Size and blocks.  The object's own size is the file's only when the file
 * has no layout, or HSM has released it; trusted.som answers otherwise, and
 * answers lazily, which is what LLAPI_SCAN_LAZY_SIZE already means.
 */
"""
DOMFN_NEW = """\t\tif (!(__le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED))
\t\t\treturn false;
\t}
\treturn true;
}

/*
 * Whether every instantiated component is on the MDT, as
 * mdt_lmm_dom_entry_check() decides for is_dom_only: then the MDT inode
 * holds the data, the MDT keeps no SOM for it (mdt_som.c), and the inode's
 * own size is the file's.  The bytes are raw from the target.
 */
static bool scan_lov_dom_only(const void *buf, size_t len)
{
\tconst struct lov_comp_md_v1 *comp = buf;
\tconst struct lov_user_md_v1 *v1;
\tbool dom = false;
\t__u16 count;
\t__u16 i;

\tif (len < sizeof(*comp) ||
\t    __le32_to_cpu(comp->lcm_magic) != LOV_MAGIC_COMP_V1)
\t\treturn false;

\tcount = __le16_to_cpu(comp->lcm_entry_count);
\tif (len < sizeof(*comp) + count * sizeof(comp->lcm_entries[0]))
\t\treturn false;
\tfor (i = 0; i < count; i++) {
\t\tconst struct lov_comp_md_entry_v1 *e = &comp->lcm_entries[i];
\t\t__u32 off = __le32_to_cpu(e->lcme_offset);

\t\tif (!(__le32_to_cpu(e->lcme_flags) & LCME_FL_INIT))
\t\t\tcontinue;
\t\tif (off > len - sizeof(*v1))
\t\t\treturn false;
\t\tv1 = (const struct lov_user_md_v1 *)((const char *)buf + off);
\t\tif (!(__le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_MDT))
\t\t\treturn false;
\t\tdom = true;
\t}
\treturn dom;
}

/*
 * Size and blocks.  The object's own size is the file's when the file has
 * no layout, HSM has released it, or all its data is on the MDT; trusted.som
 * answers otherwise, and answers lazily, which is what LLAPI_SCAN_LAZY_SIZE
 * already means.
 */
"""
DOMSIZE_OLD = """\t\treturn;
\t}

\tsom = scan_xattr(obj, LLAPI_SCAN_XA_SOM, &len);
"""
DOMSIZE_NEW = """\t\treturn;
\t}
\t/* Data-on-MDT only: the inode is the data, as an OST object is */
\tif (lov != NULL && scan_lov_dom_only(lov, len)) {
\t\trec->lfsr_stx.stx_size = obj->so_size;
\t\trec->lfsr_stx.stx_blocks = obj->so_blocks;
\t\trec->lfsr_stx.stx_mask |= STATX_SIZE | STATX_BLOCKS;
\t\treturn;
\t}

\tsom = scan_xattr(obj, LLAPI_SCAN_XA_SOM, &len);
"""

# -- c02: llapi_scan_device.3, his text --------------------------------------
MAN_DOM_OLD = """A data\\-on\\-MDT file is not one of those. Its layout is a composite one held
in
.BR trusted.lov ,
so it takes the size\\-on\\-MDT path like any other file with a layout, and
with no
.B trusted.som
written for it neither bit is set. The object's own size is the file's only
while the file fits inside the DoM component, which is a question the scan
leaves to the consumer: the layout is in
.I lfsr_lmm
for one that wants to answer it.
"""
MAN_DOM_NEW = """A data\\-on\\-MDT file whose instantiated components are all on the MDT is
one of those too: the inode holds the data, as an OST object does, and the
MDT keeps no
.B trusted.som
for it. Its size and blocks are the object's own and
.B LLAPI_SCAN_SIZE
and
.B LLAPI_SCAN_BLOCKS
are set, which is the test
.BR mdt_lmm_dom_entry_check ()
applies to the same file. One that has instantiated an OST component as well
takes the size\\-on\\-MDT path like any other file with a layout.
"""
MAN_CLS_OLD = """counter, or its sequence is not one the namespace uses.
.TP
"""
MAN_CLS_NEW = """counter, or its sequence is not one the namespace uses.
On an MDT, so is an object whose FID the namespace would use but which has no
.BR trusted.link :
the target's own files outside ROOT, such as
.I CONFIGS/mountdata
and the update logs, carry such FIDs and no name.
A file from before linkEA (Lustre 2.4) that LFSCK has not yet given one is
counted here too, having nothing on the target to say it is reachable.
.TP
"""
MAN_VIS_OLD = """pseudo\\-directory and what is under it. Their FIDs are the ones
.BR fid_is_namespace_visible ()
accepts, which is the test the MDT applies to the same question.
"""
MAN_VIS_NEW = """pseudo\\-directory and what is under it.
.BR fid_is_namespace_visible ()
accepts their FIDs, which is the MDT's own test; the scan adds the
.B trusted.link
one above, since that test passes the target's own files as well.
"""

# -- c05: a size the scan left out is undecided ----------------------------
DECL_OLD = """\tbool no_projid = false;\t/* the object has none, not one that is 0 */
\tint decision = 1;\t/* 1 is accepted; -1 is rejected. */
\tint ret = 0;
\t__u64 flags;
"""
DECL_NEW = """\tbool no_projid = false;\t/* the object has none, not one that is 0 */
\tint decision = 1;\t/* 1 is accepted; -1 is rejected. */
\tbool size_elsewhere;
\tint ret = 0;
\t__u64 flags;
"""
SIZE_OLD = """\tflags = param->fp_lmd->lmd_flags;
\tif (param->fp_check_size &&
\t    ((S_ISREG(lmd->lmd_stx.stx_mode) && stripe_count) ||
\t      S_ISDIR(lmd->lmd_stx.stx_mode)) &&
\t    !(flags & OBD_MD_FLSIZE ||
\t      (param->fp_lazy && flags & OBD_MD_FLLAZYSIZE)))
\t\tdecision = 0;

\tif (param->fp_check_blocks &&
\t    ((S_ISREG(lmd->lmd_stx.stx_mode) && stripe_count) ||
\t      S_ISDIR(lmd->lmd_stx.stx_mode)) &&
"""
SIZE_NEW = """\tflags = param->fp_lmd->lmd_flags;
\t/*
\t * A walk knows a size is elsewhere from the stripes it read.  A scan
\t * of a target has only what the scan reported, so a size it left out
\t * is undecided whatever the layout says: a file whose layout does not
\t * parse, or one the scanner has no answer for, has a stripe count of
\t * 0 too, and its stx_size is not a size.
\t */
\tsize_elsewhere = path == NULL || S_ISDIR(lmd->lmd_stx.stx_mode) ||
\t\t\t (S_ISREG(lmd->lmd_stx.stx_mode) && stripe_count);
\tif (param->fp_check_size && size_elsewhere &&
\t    !(flags & OBD_MD_FLSIZE ||
\t      (param->fp_lazy && flags & OBD_MD_FLLAZYSIZE)))
\t\tdecision = 0;

\tif (param->fp_check_blocks && size_elsewhere &&
"""

# -- the messages ------------------------------------------------------------
SOB = "Signed-off-by: Hiroshi Nishida <hnishida@thelustrecollective.com>\n"
SOB_ARTEM = "Signed-off-by: Artem Blagodarenko <ablagodarenko@thelustrecollective.com>\n"

MSG_C02_OLD = """the scanner is missing, because that is a broken install. It skips the
OST part for a ZFS, unreachable or older OST, and says so.

""" + SOB
MSG_C02_NEW = """the scanner is missing, because that is a broken install. It skips the
OST part for a ZFS, unreachable or older OST, and says so.

Two fixes by Artem Blagodarenko, found by a scan of a new filesystem:
- On an MDT, an object with a namespace FID but no trusted.link is the
  target's own, like CONFIGS/mountdata and the update logs, and is
  classified internal. trusted.link is read for every object so that
  its absence means absent. A pre-2.4 file that LFSCK has not given a
  link yet is counted internal too.
- A Data-on-MDT file whose instantiated components are all on the MDT
  gets its inode's size and blocks, as mdt_lmm_dom_entry_check() decides.
  Before, it got no size at all.

""" + SOB + SOB_ARTEM

MSG_C05_OLD = """is the id, and there is no field for the rest. Building one from the
id alone would be a FID that names a different object.

""" + SOB
MSG_C05_NEW = """is the id, and there is no field for the rest. Building one from the
id alone would be a FID that names a different object.

A size the scan did not report is undecided for -size and -blocks,
whatever the layout says: a Data-on-MDT file's stripe count is 0, so
it would otherwise be decided on a stx_size the scan never reported.
The fix is Artem Blagodarenko's.

""" + SOB + SOB_ARTEM


def add(t, msg):
    t('artem-want-cmt', DEV, WANT_CMT_OLD, WANT_CMT_NEW, since="c02")
    t('artem-want-link', DEV, WANT_LINK_OLD, WANT_LINK_NEW, since="c02")
    t('artem-haslink', DEV, HASLINK_ANCHOR, HASLINK_C02, since="c02")
    t('artem-haslink-c22', DEV, HASLINK_BODY_C02, HASLINK_BODY_C22,
      since="c22")
    t('artem-cls-hdr', DEV, CLS_HDR_OLD, CLS_HDR_NEW, since="c02")
    t('artem-cls-body', DEV, CLS_BODY_OLD, CLS_BODY_NEW, since="c02")
    t('artem-cls-call', DEV, CLS_CALL_OLD, CLS_CALL_NEW, since="c02")
    t('artem-linkea', DEV, LINKEA_OLD, LINKEA_NEW, since="c02")
    t('artem-domfn', DEV, DOMFN_OLD, DOMFN_NEW, since="c02")
    t('artem-domsize', DEV, DOMSIZE_OLD, DOMSIZE_NEW, since="c02")
    t('artem-man-dom', DEV3, MAN_DOM_OLD, MAN_DOM_NEW, since="c02")
    t('artem-man-cls', DEV3, MAN_CLS_OLD, MAN_CLS_NEW, since="c02")
    t('artem-man-vis', DEV3, MAN_VIS_OLD, MAN_VIS_NEW, since="c02")
    t('artem-decl', PFIND, DECL_OLD, DECL_NEW, since="c05")
    t('artem-size', PFIND, SIZE_OLD, SIZE_NEW, since="c05")
    t('artem-msg-c02', msg, MSG_C02_OLD, MSG_C02_NEW, since="c02")
    t('artem-msg-c05', msg, MSG_C05_OLD, MSG_C05_NEW, since="c05")
