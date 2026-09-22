#!/usr/bin/env python3
"""Hand-written transforms genfix.py cannot derive from the trees.

Two of the 09-22 lreview fixes on LU-20722 -- gating so_valid on lr_valid,
and handing over the generation of an object with no LMA -- live in
lustre/utils/libscan_kernel.c from c22, and move into the shared
lustre/utils/lustreapi_lfu_rec.h when LU-20730 (c25) extracts
scan_lfu_rec_to_obj().  genfix.py works from the tip's trees and so only
ever sees the header spelling; these are the same two fixes in the
libscan_kernel.c spelling, which c25 no longer has.  Each transform is
skipped where its old text is not found, so the pair applies to c22-c24 and
the generated pair to c25.

See [`notes.md`] for the findings themselves.
"""

KERNEL = "lustre/utils/libscan_kernel.c"

SO_VALID_OLD = "\tobj->so_valid = LLAPI_SCAN_SO_PROJID | LLAPI_SCAN_SO_BTIME;\n"

SO_VALID_NEW = """\t/*
\t * What the OSD actually filled, not what the record has room for:
\t * lr_valid is its LA_* mask, and both device backends gate these two
\t * the same way.  An inode too small for i_crtime leaves la_btime 0,
\t * and claiming it would answer "born at the epoch" where a device
\t * scan of the same target answers "not known".
\t */
\tif (lr->lr_valid & LA_PROJID)
\t\tobj->so_valid |= LLAPI_SCAN_SO_PROJID;
\tif (lr->lr_valid & LA_BTIME)
\t\tobj->so_valid |= LLAPI_SCAN_SO_BTIME;
"""

IGIF_ANCHOR = "\t/* the SOM, whole, the same way */\n"

IGIF_NEW = """\t/*
\t * No LMA, so no FID of its own recorded -- but the iterator still
\t * reported one, and on MDT0000 with os_convert_igif that is the IGIF
\t * the inode number and its generation make.  Hand the generation
\t * over the way a device backend does, so scan_rec_class() rebuilds
\t * the same FID: below the IGIF range, or where the sequence is not
\t * this object's id, there is no IGIF and so_gen stays unset.
\t */
\tif (!(lr->lr_lfu & LFU_REC_HAVE_LMA) &&
\t    lr->lr_fid_seq == lr->lr_oid &&
\t    lr->lr_fid_seq >= FID_SEQ_IGIF &&
\t    lr->lr_fid_seq <= FID_SEQ_IGIF_MAX) {
\t\tobj->so_gen = lr->lr_fid_oid;
\t\tobj->so_valid |= LLAPI_SCAN_SO_GEN;
\t}

""" + IGIF_ANCHOR


# The commit message, LU-20722's only.  find_device_nobytes() refuses on
# lfsp_got, so the refusal reaches every scan that did not answer LAYOUT --
# an OST scan through the device backends included -- and the message said
# only the new backend.  And the patch has a test now, so it says which.
MSG_REFUSE_OLD = """This backend does not claim LAYOUT, LMV or HSM, and lfs find
refuses the layout and directory stripe options with -ENOTSUP
rather than compare them against the default layout.  -links on a
directory, which counts stripes, is undecided.
"""

MSG_REFUSE_NEW = """This backend does not claim LAYOUT, LMV or HSM, and lfs find
refuses the layout and directory stripe options with -ENOTSUP
rather than compare them against the default layout.  -links on a
directory, which counts stripes, is undecided.

The refusal is on what the scan answered, not on which backend
answered it, so it reaches an OST scan through the device backends
too: "lfs find <ost> --stripe-count 2" used to be compared against
a forged default layout and is now refused.  conf-sanity 305 scans
a target while it is mounted -- counts, --paths, -name, and that
refusal -- and skips where lfu.ko is not there to read one.
"""

# and the naming half of the same commit, which the message did not mention
MSG_NAMING_OLD = """A stripe of a striped directory is marked in the record and rebuilt
as its LMV magic, so --paths does not print a shard as a directory.
"""

MSG_NAMING_NEW = """A stripe of a striped directory is marked in the record and rebuilt
as its LMV magic, so --paths does not print a shard as a directory.

Naming changes with it.  A scan reports whether its target is in
service, and lfs find takes a fid2path lookup only where that
lookup will not be sent to the target being scanned -- the target
is running, or the object is an OST object named through its owner
on an MDT.  So --fid2path on a running MDT now names what the
directory map could not place, under DNE the objects whose
ancestors are on another MDT, at one ioctl each; on a stopped one
it names no more than it did.  A changelog is read from a running
MDT, so that source says so.
"""

MSG_TESTPARAMS_OLD = "Test-Parameters: ignore\n"
MSG_TESTPARAMS_NEW = "Test-Parameters: testlist=conf-sanity env=ONLY=305\n"


def add(t, live, msg):
    """append these transforms; @t is b2bfix's t(), @live its since value"""
    t("kernel-so-valid", KERNEL, SO_VALID_OLD, SO_VALID_NEW, since=live)
    t("kernel-igif", KERNEL, IGIF_ANCHOR, IGIF_NEW, since=live)
    t("msg-refusal-reach", msg, MSG_REFUSE_OLD, MSG_REFUSE_NEW, only=[live])
    t("msg-naming", msg, MSG_NAMING_OLD, MSG_NAMING_NEW, only=[live])
    t("msg-testparams", msg, MSG_TESTPARAMS_OLD, MSG_TESTPARAMS_NEW,
      only=[live])


# ---- the released and foreign bits, in the spelling c21-c22 have ----
#
# The fill is inline in lustre/lfu/lfu_ring.c until LU-20730 extracts
# dt_otable_lfu_rec() into lustre/obdclass/dt_object.c, which genfix.py
# generates from the tip.  These are the same two additions against the
# inline spelling, plus the helper they call.
RING = "lustre/lfu/lfu_ring.c"

RING_LOV_OLD = """		rc = lfu_fill_xattr(env, iops, di, r, XATTR_NAME_LOV, buf,
				    LFU_XA_BUFLEN);
		if (rc >= 0 || rc == -ERANGE)
			lr->lr_lfu |= LFU_REC_HAVE_LOV;
"""

RING_LOV_NEW = """		rc = lfu_fill_xattr(env, iops, di, r, XATTR_NAME_LOV, buf,
				    LFU_XA_BUFLEN);
		if (rc >= 0 || rc == -ERANGE)
			lr->lr_lfu |= LFU_REC_HAVE_LOV;
		/*
		 * Not there and not readable are different answers, and a
		 * clear HAVE_LOV can only carry one of them: an -EIO here
		 * would otherwise build a record identical to a file that
		 * has no layout, and a consumer would take the MDT inode's
		 * own size for the file's.
		 */
		else if (rc != -ENODATA)
			lr->lr_lfu |= LFU_REC_XA_INCOMPLETE;
		/*
		 * The layout crosses as presence, so whether it is released
		 * has to cross as an answer: a consumer without the bytes
		 * cannot tell, and would report the pre-release size and
		 * blocks for a file that has neither.  Judged only where the
		 * whole layout was read -- -ERANGE leaves it unjudged.
		 */
		if (rc > 0 && lfu_lov_released(buf, rc))
			lr->lr_lfu |= LFU_REC_LOV_RELEASED;
"""

RING_LMV_INCOMPLETE_OLD = """		rc = lfu_fill_xattr(env, iops, di, r, XATTR_NAME_LMV, buf,
				    LFU_XA_BUFLEN);
		if (rc >= 0 || rc == -ERANGE)
			lr->lr_lfu |= LFU_REC_HAVE_LMV;
"""

RING_LMV_INCOMPLETE_NEW = """		rc = lfu_fill_xattr(env, iops, di, r, XATTR_NAME_LMV, buf,
				    LFU_XA_BUFLEN);
		if (rc >= 0 || rc == -ERANGE)
			lr->lr_lfu |= LFU_REC_HAVE_LMV;
		else if (rc != -ENODATA)
			lr->lr_lfu |= LFU_REC_XA_INCOMPLETE;
"""

RING_LMV_OLD = """		/* a stripe's LMV is the short header; a master's may not fit */
		if (rc >= (int)sizeof(__u32) &&
		    le32_to_cpu(*(__le32 *)buf) == LMV_MAGIC_STRIPE)
			lr->lr_lfu |= LFU_REC_LMV_SHARD;
"""

RING_LMV_NEW = """		/*
		 * A stripe's LMV is the short header; a master's may not fit.
		 * A foreign one is neither, and says so: a consumer given the
		 * LMV as presence would otherwise read it as a striped
		 * directory and leave its size unanswered.
		 */
		if (rc >= (int)sizeof(__u32)) {
			__u32 magic = le32_to_cpu(*(__le32 *)buf);

			if (magic == LMV_MAGIC_STRIPE)
				lr->lr_lfu |= LFU_REC_LMV_SHARD;
			else if (magic == LMV_MAGIC_FOREIGN)
				lr->lr_lfu |= LFU_REC_LMV_FOREIGN;
		}
"""

# the helper, ahead of the function that fills a record
RING_HELPER_ANCHOR = \
    "static void lfu_fill_pfid(struct lfu_rec *lr, const struct lu_fid *pfid)\n"

RING_HELPER = """/*
 * Whether HSM has released the file: every component released, decided as
 * mdt_hsm_is_released() decides it.  The bytes are raw from the target, and
 * liblustreapi's scan_lov_released() reads them the same way for a scan
 * that brought the layout across -- the two have to agree, or one file
 * answers "lfs find --size" differently depending on which read it.
 */
static bool lfu_lov_released(const void *buf, int len)
{
	const struct lov_comp_md_v1 *comp = buf;
	const struct lov_mds_md_v1 *v1 = buf;
	__u32 magic;
	__u16 count;
	__u16 i;

	if (len < (int)sizeof(*v1))
		return false;

	magic = le32_to_cpu(v1->lmm_magic);
	if (magic == LOV_MAGIC_V1 || magic == LOV_MAGIC_V3)
		return le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED;
	if (magic != LOV_MAGIC_COMP_V1 || len < (int)sizeof(*comp))
		return false;

	count = le16_to_cpu(comp->lcm_entry_count);
	if (len < (int)(sizeof(*comp) + count * sizeof(comp->lcm_entries[0])))
		return false;
	for (i = 0; i < count; i++) {
		__u32 off = le32_to_cpu(comp->lcm_entries[i].lcme_offset);

		if (off > len - sizeof(*v1))
			return false;
		v1 = (const struct lov_mds_md_v1 *)((const char *)buf + off);
		if (!(le32_to_cpu(v1->lmm_pattern) & LOV_PATTERN_F_RELEASED))
			return false;
	}
	return true;
}

""" + RING_HELPER_ANCHOR


def add_ring(t, prod):
    """the producer half, in the spelling the commits below LU-20730 have"""
    t("ring-lov-released", RING, RING_LOV_OLD, RING_LOV_NEW, since=prod)
    t("ring-lmv-incomplete", RING, RING_LMV_INCOMPLETE_OLD,
      RING_LMV_INCOMPLETE_NEW, since=prod)
    t("ring-lmv-incomplete", RING, RING_LMV_INCOMPLETE_OLD,
      RING_LMV_INCOMPLETE_NEW, since=prod)
    t("ring-lmv-foreign", RING, RING_LMV_OLD, RING_LMV_NEW, since=prod)
    t("ring-released-helper", RING, RING_HELPER_ANCHOR, RING_HELPER,
      since=prod)


# ---- the lmv_user_md_size() wrap, reported by the AI round on 68159 ----
#
# scan_lmv_to_user() exists from c02 (68156) and the 'o' bound from c05
# (68159), so these carry their own since values rather than the LIVE one
# genfix.py would give them.  genfix.py skips both by HAND_MARKERS.
LMV_CLAMP_OLD = '\tstripes = __le32_to_cpu(md->lmv_stripe_count);\n\troom = (outlen - lmv_user_md_size(0, LMV_USER_MAGIC)) /\n'

LMV_CLAMP_NEW = '\tstripes = __le32_to_cpu(md->lmv_stripe_count);\n\t/*\n\t * A count no Lustre directory can have is not a count: refused here\n\t * rather than carried, because lmv_user_md_size() returns unsigned\n\t * int and a count whose product with sizeof(struct lmv_user_mds_data)\n\t * is a multiple of 2^32 -- 0x20000000 and its multiples -- computes\n\t * back to the bare header size, so every bound built from it reads\n\t * as "the array is there" for an array that is not.\n\t */\n\tif (stripes > LMV_MAX_STRIPE_COUNT)\n\t\treturn 0;\n\troom = (outlen - lmv_user_md_size(0, LMV_USER_MAGIC)) /\n'

LMV_GUARD_OLD = '\t\t\tif (path == NULL && rec != NULL &&\n\t\t\t    rec->lfsr_lmvsize <\n\t\t\t    lmv_user_md_size(lum->lum_stripe_count,\n\t\t\t\t\t     LMV_USER_MAGIC_SPECIFIC))\n\t\t\t\tbreak;\n'

LMV_GUARD_NEW = '\t\t\t/*\n\t\t\t * Measured by the bytes, not by a product that can\n\t\t\t * wrap: lmv_user_md_size() is unsigned int, and a\n\t\t\t * count off a device whose product with the entry\n\t\t\t * size is a multiple of 2^32 computes back to the\n\t\t\t * bare header and slips through a "<" against it.\n\t\t\t */\n\t\t\tif (path == NULL && rec != NULL &&\n\t\t\t    (rec->lfsr_lmvsize <\n\t\t\t     lmv_user_md_size(0, LMV_USER_MAGIC_SPECIFIC) ||\n\t\t\t     (rec->lfsr_lmvsize -\n\t\t\t      lmv_user_md_size(0, LMV_USER_MAGIC_SPECIFIC)) /\n\t\t\t     sizeof(struct lmv_user_mds_data) <\n\t\t\t     lum->lum_stripe_count))\n\t\t\t\tbreak;\n'


def add_lmv(t, at_read, at_guard):
    """the wrap: clamped where the count is read, measured where it is used"""
    t("lmv-count-clamp", "lustre/utils/liblustreapi_scan_device.c",
      LMV_CLAMP_OLD, LMV_CLAMP_NEW, since=at_read)
    t("lmv-objects-bound", "lustre/utils/liblustreapi_pfind.c",
      LMV_GUARD_OLD, LMV_GUARD_NEW, since=at_guard)


# ---- commit-message corrections from the 09-22 AI round ----
#
# Four bodies described an earlier revision of themselves rather than the
# tree, which sends a reader of git log hunting for edits that are not in
# the diff.  Each is only ever in its own commit, so they take `only`.
MSG_FIXES = [
    # 68156: four claims against an earlier revision of itself
    ("msg-68156-otherfixes", "c02",
     "Other fixes in the scanner:\n",
     "The scanner is new here, so these are how it is written rather than\nfixes to anything in the tree:\n"),
    ("msg-68156-roottest", "c02",
     "Existing callers are not affected. A hand-written root test that also\naccepted a non-zero f_ver now uses it.\n",
     "Existing callers are not affected; its only new caller is\nscan_classify().\n"),
    ("msg-68156-example", "c02",
     "what 0 in lfsp_want means for a device scan. The man page example now\nescapes its newline correctly.\n",
     "what 0 in lfsp_want means for a device scan.\n"),
    ("msg-68156-stacktrap", "c02",
     "OST part for a ZFS, unreachable or older OST, and says so. The\nstack_trap calls no longer pass EXIT, which is the default.\n",
     "OST part for a ZFS, unreachable or older OST, and says so.\n"),
    # 68157: two edits the list leaves out, and the list invites a line-by-line
    # audit
    ("msg-68157-list", "c03",
     "- the project id 0 is written as DEFAULT_PROJID (also 0), in the code\n  and in two comments\n",
     "- the project id 0 is written as DEFAULT_PROJID (also 0), in the code\n  and in two comments\n- \"goto print;\" became \"goto decide;\", a new label in cb_find_init()\n- the fp_get_lmv/fp_check_foreign block moved out of the \"if (want != 0)\"\n  body to the top of find_decide(). It now also runs when want == 0 and\n  on the find_foreign_accepts() arm, and comes out the same either way:\n  fp_get_lmv stays 0 unless scan_rec_gather_begin() ran, and\n  lfsr_valid gains LLAPI_SCAN_LMV only in scan_rec_gather_finish(),\n  which that arm skips\n"),
    # 68158: a bullet describing an edit that is not in the diff
    ("msg-68158-phantom", "c04",
     "- \"param.\" becomes \"param->\"\n", ""),
]


def add_msgfix(t, msg):
    """the bodies that described an earlier revision of themselves"""
    for tid, at, old, new in MSG_FIXES:
        t(tid, msg, old, new, only=[at], since=at)
