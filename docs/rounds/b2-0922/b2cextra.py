#!/usr/bin/env python3
"""The 09-23 lreview fixes on 68160 (c06) and 68163 (c07), by hand.

They are not in the hand-edited trees genfix.py compares, so they are
written here and appended after every generated transform.  Each is skipped
where its old text is not found; the audit in notes.md checks that none is
skipped in a commit that still carries its old text.

See notes.md, "09-23: lreview on c06 and c07".
"""

MSG_C06 = ("llapi_name_validate(), so a typo is refused instead of matching\n",
           "llapi_name_verify(), so a typo is refused instead of matching\n")

APIH_OLD = """\t * lfs find --device, --target and --fsname: a target read directly
\t * rather than a namespace walked.  The parser has nowhere but here to
\t * put what it read; the library's find entry points look at none.
"""
APIH_NEW = """\t * lfs find --device, --target and --fsname: a target read directly
\t * rather than a namespace walked.  Only lfs uses these: its parser
\t * returns everything it reads in this struct.  The library ignores
\t * them.
"""

# c07 adds --search and re-wraps the same comment
APIH_OLD_C07 = """\t * lfs find --device, --target, --fsname and --search: a target read
\t * directly rather than a namespace walked.  The parser has nowhere but
\t * here to put what it read; the library's find entry points look at
\t * none.
"""
APIH_NEW_C07 = """\t * lfs find --device, --target, --fsname and --search: a target read
\t * directly rather than a namespace walked.  Only lfs uses these: its
\t * parser returns everything it reads in this struct.  The library
\t * ignores them.
"""

FIND1_LOCAL_OLD = """A failure the command line caused rather than the target ends the sweep:
this build having no backend for a target's type stops it there, since
every later target of that type would fail the same way.
"""
FIND1_LOCAL_NEW = """So is a target this build has no scan backend for,
and one that cannot answer an option, such as an OST asked about layouts.
"""

FIND1_BLK_OLD = """without
.BR --device .
A disk image may not, since it cannot be told apart from a file.
"""
FIND1_BLK_NEW = """without
.BR --device ,
unless the device node is itself stored on Lustre:
that is a file, and is walked as before.
A disk image may not, since it cannot be told apart from a file.
"""

LFS_INC_OLD = "#include <sys/types.h>\n#include <sys/xattr.h>\n"
LFS_INC_NEW = "#include <sys/types.h>\n#include <sys/vfs.h>\n#include <sys/xattr.h>\n"

LFS_BLK_OLD = """\t/* any of the paths, so a second target is refused and not walked */
\tfor (i = pathstart; i < pathend; i++) {
\t\tif (stat(argv[i], &st) == 0 && S_ISBLK(st.st_mode))
\t\t\treturn true;
\t}
"""
LFS_BLK_NEW = """\t/* any of the paths, so a second target is refused and not walked */
\tfor (i = pathstart; i < pathend; i++) {
\t\tstruct statfs sfs;

\t\tif (stat(argv[i], &st) != 0 || !S_ISBLK(st.st_mode))
\t\t\tcontinue;
\t\t/* a device node stored on Lustre is a file, walked as before */
\t\tif (statfs(argv[i], &sfs) == 0 && sfs.f_type == LL_SUPER_MAGIC)
\t\t\tcontinue;
\t\treturn true;
\t}
"""

KIND_OLD = """ * disabled.  Which one a device gets is decided by what the string is: a
 * block device or an image file is ldiskfs's, anything else is read as a
 * ZFS dataset name, which never names an existing file.
"""
KIND_NEW = """ * disabled.  scan_backend_kind() picks one from the string: a name that
 * begins with '/', or a relative block device or regular file, is
 * ldiskfs's; any other name is read as a ZFS dataset.
"""

DEV3_OLD = """on it in this process. The pool is exported in that second case and
exporting it again is not the answer.
"""
DEV3_NEW = """on it in this process. The pool is exported in that second case and
exporting it again is not the answer.
.IP
These checks are made when this process imports the pool. The pool stays
imported here while any scan in this process is open, and a new scan of it
in that time is not checked again: if a server has imported the pool since,
the new scan reads the pool as it was at the first import.
"""

# second lreview on c06: the message and the naming-line rule
MSG_C06_STAT = ("""- a block device given where a directory would be; lfs_find_is_device()
  checks with stat(), and a disk image is a regular file, so it needs
  --device
""", """- a block device given where a directory would be; lfs_find_is_device()
  checks with stat(), and a disk image is a regular file, so it needs
  --device. A block device node stored on Lustre is a file, and is
  walked as before: statfs() tells it apart
""")

FIND1_NAMING_OLD = """Where more than one target is read,
a line naming each one goes to standard error ahead of its objects,
"""
FIND1_NAMING_NEW = """Where the sweep finds more than one target,
a line naming each one it reads goes to standard error ahead of its objects,
"""

# second lreview on c06, finding 2: the role is after the last '-', so a
# filesystem named db-OST does not put its MDT through the OST filter
ROLE_HELPER_OLD = """\treturn dash != NULL && (size_t)(dash - label) == strlen(fsname) &&
\t       strncmp(label, fsname, dash - label) == 0;
}
"""
ROLE_HELPER_NEW = """\treturn dash != NULL && (size_t)(dash - label) == strlen(fsname) &&
\t       strncmp(label, fsname, dash - label) == 0;
}

/* Is @label's role @role ("MDT" or "OST")?  Read after the last '-' too. */
static bool lfs_find_label_is(const char *label, const char *role)
{
\tconst char *dash = strrchr(label, '-');

\treturn dash != NULL && strncmp(dash + 1, role, 3) == 0;
}
"""
ROLE_LOCAL_OLD = """\t\tif (strstr(name, "-MDT") == NULL &&
\t\t    strstr(name, "-OST") == NULL)
\t\t\tcontinue;
"""
ROLE_LOCAL_NEW = """\t\tif (!lfs_find_label_is(name, "MDT") &&
\t\t    !lfs_find_label_is(name, "OST"))
\t\t\tcontinue;
"""
ROLE_SWEEP_OLD = """\t\t    ((param->fp_obd_uuid != NULL &&
\t\t      strstr(tgts[i].lt_name, "-OST") == NULL) ||
\t\t     (param->fp_mdt_uuid != NULL &&
\t\t      strstr(tgts[i].lt_name, "-MDT") == NULL)))
"""
ROLE_SWEEP_NEW = """\t\t    ((param->fp_obd_uuid != NULL &&
\t\t      !lfs_find_label_is(tgts[i].lt_name, "OST")) ||
\t\t     (param->fp_mdt_uuid != NULL &&
\t\t      !lfs_find_label_is(tgts[i].lt_name, "MDT"))))
"""

# Artem 09-23 on 68094, and LU-20643 (68340) folded in at the user's call:
# both callers with no FID clear the record up to lmd_lmm before the
# conversion -- lmd_fid, lmd_stx, lmd_flags and lmd_lmmsize alike
STX_V1_OLD = """\tmemmove(&lmd_v2->lmd_lmm, &lmd_v1->lmd_lmm,
\t\tlmdlen - (&lmd_v2->lmd_lmm - &lmd_v1->lmd_lmm));
\tconvert_lmd_statx(lmd_v2, &st, false);
\t/*
\t * The bytes at lmd_fid are the V1 lmd_st that sat where a FID sits
\t * now -- st_dev in f_seq, the halves of st_ino in f_oid and f_ver --
\t * which reads as a plausible IGIF.
\t */
\tmemset(&lmd_v2->lmd_fid, 0, sizeof(lmd_v2->lmd_fid));
\tlmd_v2->lmd_lmmsize = 0;
\tlmd_v2->lmd_padding = 0;
"""
STX_V1_NEW = """\tmemmove(&lmd_v2->lmd_lmm, &lmd_v1->lmd_lmm,
\t\tlmdlen - (&lmd_v2->lmd_lmm - &lmd_v1->lmd_lmm));
\t/*
\t * Everything up to lmd_lmm is still the V1 lmd_st: lmd_fid would read
\t * as an IGIF and stx_mask would keep st_nlink's bits, and
\t * convert_lmd_statx() writes only the fields lstat has.
\t */
\tmemset(lmd_v2, 0, offsetof(typeof(*lmd_v2), lmd_lmm));
\tconvert_lmd_statx(lmd_v2, &st, false);
"""
STX_ENOTTY_OLD = """\t\t\tconvert_lmd_statx(lmd, &st, true);
\t\t\t/*
\t\t\t * A stat answers for an object the ioctl could not,
\t\t\t * so there is no FID: what is left at lmd_fid is the
\t\t\t * name the caller wrote there for that ioctl, which
\t\t\t * reads as a plausible IGIF.  Cleared here rather
\t\t\t * than in convert_lmd_statx(), whose third caller --
\t\t\t * cb_find_init() under gather_all -- runs after the
\t\t\t * V2 ioctl has put a real FID there.
\t\t\t */
\t\t\tmemset(&lmd->lmd_fid, 0, sizeof(lmd->lmd_fid));
"""
STX_ENOTTY_NEW = """\t\t\t/*
\t\t\t * A stat answers for an object the ioctl could not,
\t\t\t * and the buffer holds the name written in for that
\t\t\t * ioctl or the previous object: lmd_fid would read as
\t\t\t * an IGIF, stx_mask would keep the name's bits, and
\t\t\t * llapi_get_lum_file_fd() copies by lmd_lmmsize.
\t\t\t * Cleared here rather than in convert_lmd_statx(),
\t\t\t * whose third caller -- cb_find_init() under
\t\t\t * gather_all -- runs after the V2 ioctl has put real
\t\t\t * values there.
\t\t\t */
\t\t\tmemset(lmd, 0, offsetof(typeof(*lmd), lmd_lmm));
\t\t\tconvert_lmd_statx(lmd, &st, true);
"""
# c03 names the third caller find_decide() in the same comment
STX_ENOTTY_OLD_C03 = STX_ENOTTY_OLD.replace("cb_find_init() under gather_all -- runs after the",
                                            "find_decide() under gather_all -- runs after the")
STX_ENOTTY_NEW_C03 = STX_ENOTTY_NEW.replace("whose third caller -- cb_find_init() under",
                                            "whose third caller -- find_decide() under")
assert STX_ENOTTY_OLD_C03 != STX_ENOTTY_OLD and STX_ENOTTY_NEW_C03 != STX_ENOTTY_NEW
MSG_C00_STX = ("""- For an object that is not on Lustre, lmd_fid kept an old value, so
  the record got a FID made from the file name. The two callers that
  have no FID now clear it. convert_lmd_statx() no longer clears it,
  because cb_find_init() has a real FID there.
""", """- The two callers that have no FID clear the record up to lmd_lmm
  before the conversion. lmd_fid held a FID made from the file name,
  stx_mask kept bits from the V1 lmd_st or the name, which could set
  STATX_BTIME with no btime behind it, and lmd_lmmsize is the length
  llapi_get_lum_file_fd() copies by. convert_lmd_statx() clears
  nothing, because cb_find_init() has real values there. This takes
  in LU-20643, which was change 68340.
""")
MSG_C00_FIXES = ("Signed-off-by: Hiroshi Nishida <hnishida@thelustrecollective.com>\n",
                 "Fixes: 11aa7f8704c4 (\"LU-11367 som: integrate LSOM with lfs find\")\n"
                 "Signed-off-by: Hiroshi Nishida <hnishida@thelustrecollective.com>\n")

# Artem 09-23 on 68095: --mdt with no index is left out, not guessed
MDTIDX_C01_OLD = """\t\t/*
\t\t * An unstriped directory answered ENODATA, or one off Lustre
\t\t * answered ENOTTY: no stripe of its own either way.
\t\t */
"""
MDTIDX_C01_NEW = """\t\t/* --mdt cannot be answered without the index: leave it out */
\t\tif (param->fp_mdt_uuid != NULL &&
\t\t    !(rec.lfsr_valid & LLAPI_SCAN_MDT_INDEX))
\t\t\tgoto decided;

""" + MDTIDX_C01_OLD
# from c03 the guard stays in cb_find_init(), after the gather: in
# find_decide() it ran before the --foreign shortcut, whose record has no
# index, and dropped every unstriped directory under --mdt (lreview 09-23)
MDTIDX_C03_OLD = """\t\t} else {
\t\t\tstripe_count = find_get_stripe_count(param);
\t\t}
\t}

decide:
"""
MDTIDX_C03_NEW = """\t\t} else {
\t\t\tstripe_count = find_get_stripe_count(param);
\t\t}
\t\t/* --mdt cannot be answered without the index: leave it out */
\t\tif (param->fp_mdt_uuid != NULL &&
\t\t    !(rec.lfsr_valid & LLAPI_SCAN_MDT_INDEX))
\t\t\tgoto decided;
\t}

decide:
"""
MSG_C01_MDTIDX = ("""- An MDT index that cannot be fetched no longer fails the object.
""", """- An MDT index that cannot be fetched no longer fails the object.
  With --mdt, such an object is left out: it matches neither --mdt
  nor ! --mdt.
""")

# lreview c05 (2): %Li on a target scan -- an unstriped directory has no
# stub there, and fp_file_mdt_index is set only under --mdt
LI_OLD = """\t\tcase 'i':\t/* starting index */
\t\t\t/*
\t\t\t * A foreign LMV has no stripe offset: lfm_type is
"""
LI_NEW = """\t\tcase 'i':\t/* starting index */
\t\t\t/*
\t\t\t * A target scan builds no stub for an unstriped
\t\t\t * directory and sets fp_file_mdt_index only under
\t\t\t * --mdt: the record's own index answers, or nothing.
\t\t\t */
\t\t\tif (path == NULL && rec != NULL &&
\t\t\t    (lum->lum_magic == 0 ||
\t\t\t     lmv_is_foreign(lum->lum_magic))) {
\t\t\t\tif (!(rec->lfsr_valid & LLAPI_SCAN_MDT_INDEX))
\t\t\t\t\tgoto format_done;
\t\t\t\t*wrote = snprintf(buffer, size, "%d",
\t\t\t\t\t\t  (int)rec->lfsr_mdt_index);
\t\t\t\tbreak;
\t\t\t}
\t\t\t/*
\t\t\t * A foreign LMV has no stripe offset: lfm_type is
"""

# lreview c05 (4): the layout options over an OST were compared against a
# default that was never read; refused, as --mdt over an OST is.  From c22
# find_device_nobytes() refuses the same on lfsp_got; this fires first.
OSTLAY_FN_OLD = """static int find_device_targets(struct find_param *param,
\t\t\t       const struct llapi_scan_tgt *tgt)
"""
OSTLAY_FN_NEW = """/* the options only a layout answers; not --projid, which an OST has */
static bool find_asks_layout(const struct find_param *param)
{
\treturn param->fp_check_pool || param->fp_check_stripe_count ||
\t       param->fp_check_stripe_size || param->fp_check_layout ||
\t       param->fp_check_comp_count || param->fp_check_comp_end ||
\t       param->fp_check_comp_start || param->fp_check_comp_flags ||
\t       param->fp_check_mirror_count || param->fp_check_foreign ||
\t       param->fp_check_mirror_state || param->fp_check_ext_size;
}

""" + OSTLAY_FN_OLD
OSTLAY_CALL_OLD = """\t\tif (param->fp_mdt_uuid != NULL)
\t\t\tparam->fp_file_mdt_index = (int)tgt.tt_index;
\t}
"""
OSTLAY_CALL_NEW = OSTLAY_CALL_OLD + """
\t/*
\t * An OST object has no layout, so these would be compared against a
\t * default that was never read.  A target the probe cannot name is
\t * left to answer as before.
\t */
\tif (find_asks_layout(param)) {
\t\tif (param->fp_obd_uuid == NULL && param->fp_mdt_uuid == NULL &&
\t\t    scan_device_target(target, &tgt) != 0)
\t\t\ttgt.tt_flags = 0;
\t\tif (tgt.tt_flags & LLAPI_SCAN_TGT_OST) {
\t\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
\t\t\t\t    -ENOTSUP,
\t\t\t\t    "the layout options need an MDT; '%s' is an OST, whose objects carry no layout",
\t\t\t\t    tgt.tt_label);
\t\t\trc = -ENOTSUP;
\t\t\tgoto out;
\t\t}
\t}
"""
# c07 gives scan_device_target() the search path
OSTLAY_PROBE_C05 = "\t\t    scan_device_target(target, &tgt) != 0)\n"
OSTLAY_PROBE_C07 = "\t\t    scan_device_target(target, spl.lfsp_search, &tgt) != 0)\n"
MSG_C05_OSTLAY = ("""and --ost over an MDT asks about layouts, not about the target.
""", """and --ost over an MDT asks about layouts, not about the target. The
layout options over an OST are refused for the same reason: an OST
object has no layout, so they would compare a default never read.
""")

# AI round on 68415 PS14 (09-23): the MDS gate on 157d's test9, an upper
# bound on sc_size, and whole counters in the stats copy, as the siblings
T157D_OLD = """\t# -u puts the read on llapi_changelog_start_user(), which is the
\t# path that sets the server-side filter; without it the binary
\t# never exercises that call at all
\tllapi_scan_changelog_test -m $(facet_svc mds1) -d $MOUNT \\
\t\t-u $cl_user || error "llapi_scan_changelog_test failed"
"""
T157D_NEW = """\t# test9 filters on the server, with a key the MDS has only from
\t# 2.17.0 (LU-19296); an older MDS skips that case, not the rest
\tlocal skip=""

\t(( MDS1_VERSION >= $(version_code 2.17.50) )) || skip="-e 9"

\t# -u puts the read on llapi_changelog_start_user(), which is the
\t# path that sets the server-side filter; without it the binary
\t# never exercises that call at all
\tllapi_scan_changelog_test -m $(facet_svc mds1) -d $MOUNT \\
\t\t-u $cl_user $skip || error "llapi_scan_changelog_test failed"
"""
CLSIZE_OLD = """\tif (sc->sc_size < LLAPI_SCAN_CL_PARAM_MIN_SIZE)
\t\treturn -EINVAL;
"""
CLSIZE_NEW = """\tif (sc->sc_size < LLAPI_SCAN_CL_PARAM_MIN_SIZE ||
\t    sc->sc_size > LLAPI_SCAN_PARAM_MAX_SIZE)
\t\treturn -EINVAL;
"""
CLSTATS_OLD = """\t\tif (room > sizeof(sl->sl_stats))
\t\t\troom = sizeof(sl->sl_stats);
\t\tmemcpy(scl.sc_stats, &sl->sl_stats, room);
"""
CLSTATS_NEW = """\t\tif (room > sizeof(sl->sl_stats))
\t\t\troom = sizeof(sl->sl_stats);
\t\t/* a whole counter, never half of one */
\t\troom = scan_stats_whole(room);
\t\tmemcpy(scl.sc_stats, &sl->sl_stats, room);
"""

# AI round on 68163 PS22, user's call 09-23: ENOTSUP no longer ends a
# --local/--fsname sweep -- one backend per kind of target since c07, and
# an OST refuses the layout options an MDT answers
SWEEP_CODE_OLD = """\t\t\tif (ret == 0)
\t\t\t\tret = rc;
\t\t\tif (rc == -ENOTSUP)
\t\t\t\tbreak;
"""
SWEEP_CODE_NEW = """\t\t\tif (ret == 0)
\t\t\t\tret = rc;
"""
SWEEP_CMT_OLD = """ * A sweep skips the targets --ost or --mdt cannot name.  After that, ENOTSUP
 * ends the sweep: a predicate a target scan cannot answer is a property of
 * the command line, and would fail the same way for every remaining target.
"""
SWEEP_CMT_NEW = """ * A sweep skips the targets --ost or --mdt cannot name.  ENOTSUP does not
 * end it: an OST cannot answer everything an MDT can, and a node may serve
 * a kind of target this build has no backend for.
"""
MSG_C06_SWEEP = ("""the targets of the other type, which those options cannot name. After
that, ENOTSUP ends the sweep: it comes from the command line, and would
fail the same way for every remaining target.
""", """the targets of the other type, which those options cannot name.
ENOTSUP does not end a sweep either: an OST cannot answer everything an
MDT can, and a node may serve a kind of target this build cannot read.
""")


def add(t, msg):
    t('c00-stx-v1', "lustre/utils/liblustreapi_pfind.c", STX_V1_OLD,
      STX_V1_NEW, since="c00")
    t('c00-stx-enotty', "lustre/utils/liblustreapi_pfind.c", STX_ENOTTY_OLD,
      STX_ENOTTY_NEW, since="c00")
    t('c03-stx-enotty', "lustre/utils/liblustreapi_pfind.c",
      STX_ENOTTY_OLD_C03, STX_ENOTTY_NEW_C03, since="c03")
    t('c00-msg-stx', msg, MSG_C00_STX[0], MSG_C00_STX[1], since="c00")
    t('c00-msg-fixes', msg, MSG_C00_FIXES[0], MSG_C00_FIXES[1], only=["c00"],
      since="c00")
    t('c01-mdtidx', "lustre/utils/liblustreapi_pfind.c", MDTIDX_C01_OLD,
      MDTIDX_C01_NEW, since="c01")
    t('c03-mdtidx', "lustre/utils/liblustreapi_pfind.c", MDTIDX_C03_OLD,
      MDTIDX_C03_NEW, since="c03")
    t('c01-msg-mdtidx', msg, MSG_C01_MDTIDX[0], MSG_C01_MDTIDX[1],
      since="c01")
    t('c05-li', "lustre/utils/liblustreapi_pfind.c", LI_OLD, LI_NEW,
      since="c05")
    t('c05-ostlay-fn', "lustre/utils/liblustreapi_pfind.c", OSTLAY_FN_OLD,
      OSTLAY_FN_NEW, since="c05")
    t('c05-ostlay-call', "lustre/utils/liblustreapi_pfind.c",
      OSTLAY_CALL_OLD, OSTLAY_CALL_NEW, since="c05")
    t('c07-ostlay-probe', "lustre/utils/liblustreapi_pfind.c",
      OSTLAY_PROBE_C05, OSTLAY_PROBE_C07, since="c07")
    t('c05-msg-ostlay', msg, MSG_C05_OSTLAY[0], MSG_C05_OSTLAY[1],
      since="c05")
    t('c09-157d-gate', "lustre/tests/sanity.sh", T157D_OLD, T157D_NEW,
      since="c09")
    t('c09-clsize', "lustre/utils/liblustreapi_scan_changelog.c",
      CLSIZE_OLD, CLSIZE_NEW, since="c09")
    t('c09-clstats', "lustre/utils/liblustreapi_scan_changelog.c",
      CLSTATS_OLD, CLSTATS_NEW, since="c09")
    t('c06-sweep-code', "lustre/utils/lfs.c", SWEEP_CODE_OLD, SWEEP_CODE_NEW,
      since="c06")
    t('c06-sweep-cmt', "lustre/utils/lfs.c", SWEEP_CMT_OLD, SWEEP_CMT_NEW,
      since="c06")
    t('c06-msg-sweep', msg, MSG_C06_SWEEP[0], MSG_C06_SWEEP[1], since="c06")
    t('c06-msg-verify', msg, MSG_C06[0], MSG_C06[1], since="c06")
    t('c06-msg-stat', msg, MSG_C06_STAT[0], MSG_C06_STAT[1], since="c06")
    t('c06-find1-naming', "Documentation/man1/lfs-find.1", FIND1_NAMING_OLD,
      FIND1_NAMING_NEW, since="c06")
    t('c06-apih-comment', "include/lustre/lustreapi.h", APIH_OLD, APIH_NEW,
      since="c06")
    t('c07-apih-comment', "include/lustre/lustreapi.h", APIH_OLD_C07,
      APIH_NEW_C07, since="c07")
    t('c06-find1-local', "Documentation/man1/lfs-find.1", FIND1_LOCAL_OLD,
      FIND1_LOCAL_NEW, since="c06")
    t('c06-find1-blk', "Documentation/man1/lfs-find.1", FIND1_BLK_OLD,
      FIND1_BLK_NEW, since="c06")
    t('c06-lfs-inc', "lustre/utils/lfs.c", LFS_INC_OLD, LFS_INC_NEW,
      since="c06")
    t('c06-lfs-blk', "lustre/utils/lfs.c", LFS_BLK_OLD, LFS_BLK_NEW,
      since="c06")
    t('c06-role-helper', "lustre/utils/lfs.c", ROLE_HELPER_OLD,
      ROLE_HELPER_NEW, since="c06")
    t('c06-role-local', "lustre/utils/lfs.c", ROLE_LOCAL_OLD, ROLE_LOCAL_NEW,
      since="c06")
    t('c06-role-sweep', "lustre/utils/lfs.c", ROLE_SWEEP_OLD, ROLE_SWEEP_NEW,
      since="c06")
    t('c07-kind-comment', "lustre/utils/liblustreapi_scan_device.c",
      KIND_OLD, KIND_NEW, since="c07")
    t('c07-dev3-nested', "Documentation/man3/llapi_scan_device.3",
      DEV3_OLD, DEV3_NEW, since="c07")
