#!/usr/bin/env python3
"""The 09-23 minor batch: lreview on c00-c06 and the AI rounds on 68163,
68288 and 68416, text and small fixes.  See notes.md, "The minor batch".
"""

PFIND = "lustre/utils/liblustreapi_pfind.c"

# -- c00 message (lreview c00 1, 2) -------------------------------------------
MSG_C00_MAX = ("""  Bytes past this library's definition must be zero, up to
  LLAPI_SCAN_PARAM_MAX_SIZE (4096 bytes). Only whole fields are
""", """  Bytes past this library's definition must be zero, up to 4096
  bytes. Only whole fields are
""")
MSG_C00_NEW = ("""- llapi_scan_get_lmv() also clears lum_pool_name, which kept the
  previous directory's value.
- A foreign directory's LMV is not changed. Writing the MDT index at
  offset 8 overwrote the foreign type.
- STATX_INO is added to LLAPI_SCAN_MDT_MASK. Asked for alone, it came
  back as zero with its bit clear.
- LLAPI_SCAN_LMV_FOREIGN asked for alone now also fetches the LMV.
""", """
In the new code: llapi_scan_get_lmv() clears lum_pool_name, so it
never keeps the previous directory's value, and leaves a foreign
directory's LMV alone, since its type is where the MDT index would be
written. STATX_INO is in LLAPI_SCAN_MDT_MASK, because only the ioctl
answers it. LLAPI_SCAN_LMV_FOREIGN asked for alone fetches the LMV.
""")
MSG_C00_TESTS = ("""test10 scans a tree that is not Lustre: the stat fields are set, and
FID, layout, LMV, MDT index and HSM are clear. It skips itself when
the tree is on Lustre.
""", """lustre/tests/llapi_scan_test.c is new, and sanity test_157c runs it.
Tests 0-9 cover every object once at any thread count, the depth
limit, a consumer stopping the scan, the demand mask, the filter, bad
arguments, the project id, the HSM state and the layout. test10 scans
a tree that is not Lustre: the stat fields are set, and FID, layout,
LMV, MDT index and HSM are clear. It skips itself when the tree is on
Lustre.
""")

# -- c00 code comments, man page, test (lreview c00 4-8) ----------------------
SCANC_OLD = """\t/*
\t * fp_lmd is one buffer for the whole scan, and the lstat() fallback
\t * builds lmd_stx field by field rather than replacing it, so
\t * STATX_BTIME in stx_mask and a non-zero stx_attributes_mask would
\t * otherwise survive from the previous object and be reported as this
\t * one's.  An object off Lustre keeps its record --
\t * llapi_scan_get_lmv() lets ENOTTY through on purpose -- so this is
\t * reached whenever a scan crosses onto a non-Lustre subtree.
\t * lmd_fid needs no clear here: the fallback in get_lmd_info_fd()
\t * clears it beside its own convert_lmd_statx() call.
\t */
"""
SCANC_NEW = """\t/*
\t * fp_lmd is one buffer for the whole scan.  get_lmd_info_fd() fills
\t * or clears lmd_stx on every path it takes; this is the cheap
\t * guarantee that nothing of the previous object's is left if a later
\t * change adds one that does not.
\t */
"""
INTH_OLD = """ * to reach the MDT.  LLAPI_SCAN_STATX_MASK promises the whole low half,
 * named or not, so asking for it is legal and used to return zero with
 * the bit clear.
"""
INTH_NEW = """ * to reach the MDT.  LLAPI_SCAN_STATX_MASK promises the whole low half,
 * named or not, so asking for it alone is legal.
"""
MAN_HLD_OLD = """names it and the filesystem supports project quotas. This is the HLD's POSIX Input
Scanner: the same traversal with a different attribute source, rather than a
second scanner.
"""
MAN_HLD_NEW = """names it and the filesystem supports project quotas. It is the same walk with
.BR stat (2)
as the attribute source, not a second scanner.
"""
MAN_RET_OLD = """a negative errno on failure, or the value
.I lfsp_filter
returned to stop the scan, passed back unchanged."""
MAN_RET_NEW = """a negative errno on failure, or the negative value
.I cb
or
.I lfsp_filter
returned to stop the scan, passed back unchanged."""
TEST400_OLD = """\tASSERTF(res.res_gathered == res.res_count,
"""
TEST400_NEW = """\t/* each delivered record passed the filter, and was gathered after */
\tASSERTF(res.res_gathered == res.res_count,
"""

# -- c01 (lreview c01 1), c02 (lreview c02 3), c05 (lreview c05 1, 3) ------
MSG_C01_FIXES = ("""Fixes: 3dad616e09fc ("LU-4017 quota: add project id support to lfs find")
""", """Fixes: 3dad616e09fc ("LU-4017 quota: add project id support to lfs find")
Fixes: 501e5b2c8a47 ("LU-18027 lfs: lfs find handling special files")
""")
MSG_C02_LSTDDEF = ("""OST part for a ZFS, unreachable or older OST, and says so.

Two fixes by Artem Blagodarenko""", """OST part for a ZFS, unreachable or older OST, and says so.

lustreapi_internal.h no longer includes lstddef.h: nothing in it uses
ARRAY_SIZE any more, and the include reached 27 files.

Two fixes by Artem Blagodarenko""")
BLANK2_OLD = "#include <linux/lustre/lustre_kernelcomm.h>\n\n\n#include <lustre/lustreapi.h>\n"
BLANK2_NEW = "#include <linux/lustre/lustre_kernelcomm.h>\n\n#include <lustre/lustreapi.h>\n"
MSG_C05_IGIF = ("""An MDT object with no trusted.lma keeps obj:ID for the same kind of
reason, from the other direction: an IGIF is the inode number and its
generation, and the record carries no generation -- lfsr_stx.stx_ino
is the id, and there is no field for the rest. Building one from the
id alone would be a FID that names a different object.
""", """An MDT object with no trusted.lma keeps obj:ID unless it is on
MDT0000, where its IGIF is built from the inode number and generation,
as osd_scrub.c does. Elsewhere there is nothing to build a FID from:
an IGIF belongs to MDT0000 only, and a ZFS object id is wider than an
IGIF holds.
""")
NULLCMT_OLD = """ * find_get_projid() is what tests fc_path today; setup_target_indexes(),
 * find_check_xattrs(), the lstat_f() arm and the printing still take it
 * unconditionally, and reach llistxattr(NULL) and lstat(NULL) if it is not
 * there.  Nothing passes NULL to those yet -- a target scan is decided
 * before them -- and the caller that does will have to guard them, so this
 * says which steps are covered rather than claiming they all are.
"""
NULLCMT_NEW = """ * A target scan passes no path.  find_get_projid() tests fc_path itself,
 * and the other steps that take it are kept from NULL elsewhere: --xattr is
 * refused before the scan, setup_target_indexes() runs only where
 * lustre_fs is set, which a scan leaves 0, the stat arm counts the object
 * undecided when there is no path, descriptor or dirent, and the printing
 * tests the path where it needs one.
"""

DEV = "lustre/utils/liblustreapi_scan_device.c"
MAN3FD = "Documentation/man3/llapi_find_device.3"

# -- c07: the two routing comments (AI on 68163 PS22) -----------------------
KINDTAIL_OLD = """\t * named "pool/dataset" and is not a path.  A name that begins with a
\t * slash never reaches here -- the test above takes it, and
\t * scan_device_exists() has already answered -errno for one that does
\t * not exist, which is what keeps "lfs find --device /dev/sdb99" from
\t * being reported as a missing ZFS backend on a node that has no ZFS.
\t */
"""
KINDTAIL_NEW = """\t * named "pool/dataset" and is not a path.  A name that begins with a
\t * slash never reaches here: the test above sends it to ldiskfs.
\t */
"""
EXISTS_OLD = """ * A pathname that is not there is not a ZFS dataset.
 *
 * scan_backend_kind() answers ZFS for anything that is not a block device or
 * a regular file, which is right for a dataset name -- "pool/mdt0" does not
 * stat -- and wrong for "/dev/mapper/gone".  Left to it, a mistyped or
 * torn-down device is reported as a missing ZFS backend, which sends the
 * reader looking for a package rather than at the name they typed.  Only a
 * leading '/' distinguishes the two: a dataset name never has one.
 */
"""
EXISTS_NEW = """ * A pathname that is not there is not a target.
 *
 * scan_backend_kind() sends every name that begins with '/' to ldiskfs, so
 * on a build with no ldiskfs backend a mistyped or torn-down device would
 * come back as a missing backend, which sends the reader looking for a
 * package rather than at the name they typed.  The real errno is answered
 * first: -ENOENT, or -ENOTDIR, -ELOOP or -EACCES as stat() finds them.
 */
"""

# -- c10: "The last" twice (AI on 68416 PS14) -------------------------------
THELAST_OLD = """The last is cleared rather than filled for the caller: it would report the
demand mask the search settled on and not the one the caller asked for.
The last goes because there is no caller data to pair a filter with: the
"""
THELAST_NEW = """.I lfsp_got
is cleared rather than filled for the caller: it would report the
demand mask the search settled on and not the one the caller asked for.
.I lfsp_filter
goes because there is no caller data to pair a filter with: the
"""

# -- c08: 68288's message, lfs-find.1 and llapi_find_device.3 --------------
MSG_C08_MEM = ("""A directory map entry keeps its name inline, about 288 bytes, so a
million directories use about 288 MB, and 1.5 times that while
scan_dirmap_grow() holds both tables. Keeping names in an arena would
use less.""", """A directory map entry keeps its name inline, 288 bytes, and the table
is a power of two at most three quarters full: a million directories
use a 2^21-entry table, about 576 MiB, and about 864 MiB while
scan_dirmap_grow() holds both tables. Keeping names in an arena would
use less.""")
SEEALSO_OLD = """.BR lfs (1),
.BR lfs-getdirstripe (1),
"""
SEEALSO_NEW = """.BR lfs (1),
.BR lfs-fid2path (1),
.BR lfs-getdirstripe (1),
"""
# c12 adds lfs-changelog(1) between lfs(1) and lfs-getdirstripe(1)
SEEALSO_C12_OLD = """.BR lfs-changelog (1),
.BR lfs-getdirstripe (1),
"""
SEEALSO_C12_NEW = """.BR lfs-changelog (1),
.BR lfs-fid2path (1),
.BR lfs-getdirstripe (1),
"""
EXDEV_OLD = """.B -EXDEV
.I lfsp_fsname
is set and
.I target
belongs to another filesystem.
"""
EXDEV_NEW = """.B -EXDEV
.I target
belongs to another filesystem than the one it is compared with: that of
.I fp_fid2path_mnt
where the search has one, and
.I lfsp_fsname
otherwise.
"""
NOTES_OLD = """of another resolves it happily and answers with its own pathname \\(em set
.I lfsp_fsname
on
.I sp
and the scan refuses a target of any other filesystem with
.BR -EXDEV .
"""
NOTES_NEW = """of another resolves it happily and answers with its own pathname \\(em so the
filesystem of that mount is compared with the target's label, and a target of
any other filesystem is refused with
.BR -EXDEV .
.I fp_paths
and a plain
.BR llapi_scan_device ()
caller have no mount, and set
.I lfsp_fsname
on
.I sp
for the same check.
"""

# -- c02: llapi_scan_device.3 -- shards, HSM, the always-read link --------
DEV3 = "Documentation/man3/llapi_scan_device.3"
VIS_OLD = """reachable from the namespace \\(em a file or directory a client can name.
"""
VIS_NEW = """reachable from the namespace \\(em a file or directory a client can name.
Each shard of a striped directory is one too, with a name of its own in
.BR trusted.link ,
so a directory striped over N MDTs is N+1 records across their scans.
"""
HSM_OLD = """which a device answers for from the object itself where a namespace scan
pays an ioctl.
"""
HSM_NEW = """which a device answers for from the object itself where a namespace scan
pays an ioctl.
It is set only for an object that has a
.BR trusted.hsm ;
a namespace scan sets it with no states for any regular file, which the
MDT answers for even where the file was never archived.
"""
ALWAYS_OLD = """.B trusted.lma
is always read: without it an object has neither a FID nor a class.
"""
ALWAYS_NEW = """.B trusted.lma
and
.B trusted.link
are always read: without the first an object has neither a FID nor a class,
and on an MDT the second is what tells a file from the target's own.
"""

# -- c06: conf-sanity 300 on a multi-node cluster (lreview c06 1) ----------
CS300_OLD = """\t\techo "not sweeping: mds1 and ost1 are not one ldiskfs node"
\tfi

\t# and now the same objects, read off the device with nothing mounted:
"""
CS300_NEW = """\t\techo "not sweeping: mds1 and ost1 are not one ldiskfs node"
\tfi

\t# --target and --fsname while mds1 is up, which is where they are meant
\t# to answer; the sweep above runs only where mds1 and ost1 share a node.
\t# ldiskfs only: a ZFS pool in use is refused.
\tif [[ "$mds1_FSTYPE" == ldiskfs ]]; then
\t\tlocal mdt1svc=$(facet_svc mds1)
\t\tlocal n

\t\tn=$(do_facet mds1 "$LFS find --target $mdt1svc --type f" \\
\t\t\t2> $scan_err | wc -l)
\t\t(( n > 0 )) || {
\t\t\tcat $scan_err
\t\t\terror "lfs find --target $mdt1svc found no files"
\t\t}
\t\tn=$(do_facet mds1 \\
\t\t\t"$LFS find --fsname $FSNAME --mdt $mdt1svc --type f" \\
\t\t\t2> $scan_err | wc -l)
\t\t(( n > 0 )) || {
\t\t\tcat $scan_err
\t\t\terror "--fsname $FSNAME --mdt $mdt1svc found no files"
\t\t}
\tfi

\t# and now the same objects, read off the device with nothing mounted:
"""

# -- c08: the pre-pass skips non-directories before their xattrs (AI on
# 68288 PS16, measured 09-23: 64% of the pass on a 300k-file MDT) --------
INT = "lustre/utils/lustreapi_internal.h"
PPF_FIELD_OLD = "\tllapi_scan_cb_t\t pp_cb;\n"
PPF_FIELD_NEW = """\tllapi_scan_cb_t\t pp_cb;
\t/* before any xattr is read; NULL: none */
\tllapi_scan_cb_t\t pp_filter;
"""
PPF_FN_OLD = """/*
 * Set up the map and the pass that fills it:"""
PPF_FN_NEW = """/* the map holds directories: the rest is dropped before its xattrs */
static int scan_dirmap_filter(const struct llapi_scan_rec *rec, void *data)
{
\treturn S_ISDIR(rec->lfsr_stx.stx_mode) ? 0 : 1;
}

""" + PPF_FN_OLD
PPF_SET_OLD = "\tpre->pp_cb = scan_dirmap_cb;\n"
PPF_SET_NEW = "\tpre->pp_cb = scan_dirmap_cb;\n\tpre->pp_filter = scan_dirmap_filter;\n"
PPF_RUN_OLD = """\t\t/* lfsp_filter is the caller's, and it is paired with the
\t\t * caller's own data: a pre-pass has neither
\t\t */
\t\tdev.sd_filter = NULL;
"""
PPF_RUN_NEW = """\t\t/* lfsp_filter is the caller's, paired with the caller's own
\t\t * data: a pre-pass brings its own, or none
\t\t */
\t\tdev.sd_filter = pre->pp_filter;
"""
MSG_C08_PPF = ("""Documentation: lfs-find.1 describes both options""", """The pre-pass drops every object that is not a directory before its
xattrs are read, through a filter of its own. On a 300,000-file MDT
that was about two thirds of the pass.

Documentation: lfs-find.1 describes both options""")


def add(t, msg):
    t('m-c00-max', msg, MSG_C00_MAX[0], MSG_C00_MAX[1], since="c00")
    t('m-c00-new', msg, MSG_C00_NEW[0], MSG_C00_NEW[1], since="c00")
    t('m-c00-scanc', "lustre/utils/liblustreapi_scan.c", SCANC_OLD,
      SCANC_NEW, since="c00")
    t('m-c00-inth', "lustre/utils/lustreapi_internal.h", INTH_OLD, INTH_NEW,
      since="c00")
    t('m-c00-man-hld', "Documentation/man3/llapi_scan_namespace.3",
      MAN_HLD_OLD, MAN_HLD_NEW, since="c00")
    t('m-c00-man-ret', "Documentation/man3/llapi_scan_namespace.3",
      MAN_RET_OLD, MAN_RET_NEW, since="c00")
    t('m-c00-test400', "lustre/tests/llapi_scan_test.c", TEST400_OLD,
      TEST400_NEW, since="c00")
    t('m-c01-fixes', msg, MSG_C01_FIXES[0], MSG_C01_FIXES[1], only=["c01"],
      since="c01")
    t('m-c02-lstddef', msg, MSG_C02_LSTDDEF[0], MSG_C02_LSTDDEF[1],
      since="c02")
    t('m-c02-blank2', "lustre/utils/lustreapi_internal.h", BLANK2_OLD,
      BLANK2_NEW, since="c02")
    t('m-c05-igif', msg, MSG_C05_IGIF[0], MSG_C05_IGIF[1], since="c05")
    t('m-c05-nullcmt', PFIND, NULLCMT_OLD, NULLCMT_NEW, since="c05")
    t('m-c07-kindtail', DEV, KINDTAIL_OLD, KINDTAIL_NEW, since="c07")
    t('m-c07-exists', DEV, EXISTS_OLD, EXISTS_NEW, since="c07")
    t('m-c10-thelast', MAN3FD, THELAST_OLD, THELAST_NEW, since="c10")
    t('m-c08-mem', msg, MSG_C08_MEM[0], MSG_C08_MEM[1], since="c08")
    t('m-c08-seealso', "Documentation/man1/lfs-find.1", SEEALSO_OLD,
      SEEALSO_NEW, since="c08")
    t('m-c12-seealso', "Documentation/man1/lfs-find.1", SEEALSO_C12_OLD,
      SEEALSO_C12_NEW, since="c12")
    t('m-c08-exdev', MAN3FD, EXDEV_OLD, EXDEV_NEW, since="c08")
    t('m-c08-notes', MAN3FD, NOTES_OLD, NOTES_NEW, since="c08")
    t('m-c02-vis', DEV3, VIS_OLD, VIS_NEW, since="c02")
    t('m-c02-hsm', DEV3, HSM_OLD, HSM_NEW, since="c02")
    t('m-c02-always', DEV3, ALWAYS_OLD, ALWAYS_NEW, since="c02")
    t('m-c06-cs300', "lustre/tests/conf-sanity.sh", CS300_OLD, CS300_NEW,
      since="c06")
    t('m-c08-ppf-field', INT, PPF_FIELD_OLD, PPF_FIELD_NEW, since="c08")
    t('m-c08-ppf-fn', DEV, PPF_FN_OLD, PPF_FN_NEW, since="c08")
    t('m-c08-ppf-set', DEV, PPF_SET_OLD, PPF_SET_NEW, since="c08")
    t('m-c08-ppf-run', DEV, PPF_RUN_OLD, PPF_RUN_NEW, since="c08")
    t('m-c08-ppf-msg', msg, MSG_C08_PPF[0], MSG_C08_PPF[1], since="c08")
    t('m-c00-tests', msg, MSG_C00_TESTS[0], MSG_C00_TESTS[1], since="c00")
