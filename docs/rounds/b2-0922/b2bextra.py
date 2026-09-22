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
		 * The layout crosses as presence, so whether it is released
		 * has to cross as an answer: a consumer without the bytes
		 * cannot tell, and would report the pre-release size and
		 * blocks for a file that has neither.  Judged only where the
		 * whole layout was read -- -ERANGE leaves it unjudged.
		 */
		if (rc > 0 && lfu_lov_released(buf, rc))
			lr->lr_lfu |= LFU_REC_LOV_RELEASED;
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
    t("ring-lmv-foreign", RING, RING_LMV_OLD, RING_LMV_NEW, since=prod)
    t("ring-released-helper", RING, RING_HELPER_ANCHOR, RING_HELPER,
      since=prod)
