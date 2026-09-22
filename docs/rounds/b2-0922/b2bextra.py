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
