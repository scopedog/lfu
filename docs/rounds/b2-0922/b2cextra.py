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
FIND1_LOCAL_NEW = """The sweep stops at the first target that fails with
.BR ENOTSUP :
an option a target scan cannot answer,
or no scan backend in this build for that target's type.
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

# Artem 09-23 on 68094: lmd_stx holds old bytes, and stx_mask is only ORed
STX_V1_OLD = """\tmemmove(&lmd_v2->lmd_lmm, &lmd_v1->lmd_lmm,
\t\tlmdlen - (&lmd_v2->lmd_lmm - &lmd_v1->lmd_lmm));
\tconvert_lmd_statx(lmd_v2, &st, false);
"""
STX_V1_NEW = """\tmemmove(&lmd_v2->lmd_lmm, &lmd_v1->lmd_lmm,
\t\tlmdlen - (&lmd_v2->lmd_lmm - &lmd_v1->lmd_lmm));
\t/* the V1 lmd_st is still here: stx_mask would keep st_nlink's bits */
\tmemset(&lmd_v2->lmd_stx, 0, sizeof(lmd_v2->lmd_stx));
\tconvert_lmd_statx(lmd_v2, &st, false);
"""
STX_ENOTTY_OLD = """\t\t\tconvert_lmd_statx(lmd, &st, true);
\t\t\t/*
\t\t\t * A stat answers for an object the ioctl could not,
"""
STX_ENOTTY_NEW = """\t\t\t/* the name written for the ioctl is still here */
\t\t\tmemset(&lmd->lmd_stx, 0, sizeof(lmd->lmd_stx));
\t\t\tconvert_lmd_statx(lmd, &st, true);
\t\t\t/*
\t\t\t * A stat answers for an object the ioctl could not,
"""
MSG_C00_STX = ("""  have no FID now clear it. convert_lmd_statx() no longer clears it,
  because cb_find_init() has a real FID there.
""", """  have no FID now clear it. convert_lmd_statx() no longer clears it,
  because cb_find_init() has a real FID there.
- The same two callers clear lmd_stx. It held the old V1 lmd_st or
  the file name, and convert_lmd_statx() only adds bits to stx_mask,
  so a long name could set STATX_BTIME with no btime behind it.
""")

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


def add(t, msg):
    t('c00-stx-v1', "lustre/utils/liblustreapi_pfind.c", STX_V1_OLD,
      STX_V1_NEW, since="c00")
    t('c00-stx-enotty', "lustre/utils/liblustreapi_pfind.c", STX_ENOTTY_OLD,
      STX_ENOTTY_NEW, since="c00")
    t('c00-msg-stx', msg, MSG_C00_STX[0], MSG_C00_STX[1], since="c00")
    t('c01-mdtidx', "lustre/utils/liblustreapi_pfind.c", MDTIDX_C01_OLD,
      MDTIDX_C01_NEW, since="c01")
    t('c03-mdtidx', "lustre/utils/liblustreapi_pfind.c", MDTIDX_C03_OLD,
      MDTIDX_C03_NEW, since="c03")
    t('c01-msg-mdtidx', msg, MSG_C01_MDTIDX[0], MSG_C01_MDTIDX[1],
      since="c01")
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
