#!/usr/bin/env python3
"""Batch 2's lreview fixes for 68288, 2026-09-21 evening.

Seven findings, none a defect by the reviewer's own severity. Four taken:

  - the dirmap is handed over when the pre-pass RAN, not when it found
    something. The code's own comment already says "the map is used whenever
    it was built"; the dm_used test contradicted it for an MDT whose files
    all sit in the filesystem root, sending --fid2path to one
    llapi_fid2path_at() per object against a target that may be out of
    service. scan_device_run_prepass() already refuses to answer this
    question from the answer rather than the target (see its comment at the
    pp_tgt_flags gate), so the flag is set where the pre-pass sweeps.
  - --paths and --fid2path refused together in the library, not only in lfs.
  - the man page sentence that says a match is always printed as a FID.
  - two EXAMPLES lines for the new options.

Not taken: the -Waddress-of-packed-member claim (ff_parent is at offset 0 and
gcc -Wall does not warn -- checked), and the --local sweep skipping OSTs under
--paths, which belongs to 68160 and is already pushed.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "r3-0913"))
import r3fix  # noqa: E402

MSG = r3fix.MSG
r3fix.ORDER = ["c%02d" % i for i in range(64)]
T = []


def t(tid, path, old, new, only=None, since=None, count_all=False):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=count_all))


PFIND = "lustre/utils/liblustreapi_pfind.c"
DEV = "lustre/utils/liblustreapi_scan_device.c"
INT = "lustre/utils/lustreapi_internal.h"
FIND1 = "Documentation/man1/lfs-find.1"

# ============ the pre-pass reports that it ran, rather than being guessed at
t("prepass-ran-field", INT,
  "\t__u64\t\t*pp_skipped;\t/* out or NULL: skipped by the pass */\n",
  "\t__u64\t\t*pp_skipped;\t/* out or NULL: skipped by the pass */\n"
  "\t/* out or NULL: set when the pre-pass actually swept the target */\n"
  "\tbool\t\t*pp_ran;\n", since="c08")

t("prepass-ran-set", DEV,
  "\tif (pre != NULL && pre->pp_cb != NULL) {\n"
  "\t\tstruct llapi_scan_stats prestats = { 0 };\n",
  "\tif (pre != NULL && pre->pp_cb != NULL) {\n"
  "\t\tstruct llapi_scan_stats prestats = { 0 };\n"
  "\t\t/* the caller's own answer to \"was a map built for this\n"
  "\t\t * target\", which it cannot get from the map's contents\n"
  "\t\t */\n"
  "\t\tif (pre->pp_ran != NULL)\n"
  "\t\t\t*pre->pp_ran = true;\n", since="c08")

t("dirmap-state", PFIND,
  "\t/* every directory on the target, empty unless it is an MDT */\n"
  "\tstruct scan_dirmap\t fds_dirmap;\n"
  "};\n",
  "\t/* every directory on the target, empty unless it is an MDT */\n"
  "\tstruct scan_dirmap\t fds_dirmap;\n"
  "\t/* whether the pre-pass swept: an MDT's map may be built and empty */\n"
  "\tbool\t\t\t fds_dirmap_built;\n"
  "};\n", since="c08")

t("dirmap-gate", PFIND,
  "\t/*\n"
  "\t * --paths has only the map, even an empty one: falling through to the\n"
  "\t * FID print would name an object --paths promised to count instead.\n"
  "\t */\n"
  "\tfc.fc_dirmap = st->fds_dirmap.dm_used != 0 || param->fp_paths ?\n"
  "\t\t       &st->fds_dirmap : NULL;\n",
  "\t/*\n"
  "\t * Built, not non-empty: an MDT whose files all sit in the filesystem\n"
  "\t * root ends the pre-pass with dm_used == 0 -- ROOT, .lustre and\n"
  "\t * lost+found carry no trusted.link, so scan_dirmap_cb() inserts\n"
  "\t * none of them -- and composing still answers, scan_dirmap_path()\n"
  "\t * stopping at LU_ROOT_FID without a lookup.  Keying on the contents\n"
  "\t * sent --paths to the FID print and --fid2path to one\n"
  "\t * llapi_fid2path_at() per object against the target being scanned,\n"
  "\t * which is the lookup this path exists to avoid.  An OST leaves the\n"
  "\t * flag clear, so --fid2path still names its objects through the\n"
  "\t * mount.\n"
  "\t */\n"
  "\tfc.fc_dirmap = st->fds_dirmap_built ? &st->fds_dirmap : NULL;\n",
  since="c08")

t("prepass-ran-wire", PFIND,
  "\t\tpre.pp_skipped = &pre_skipped;\n",
  "\t\tpre.pp_skipped = &pre_skipped;\n"
  "\t\tpre.pp_ran = &st.fds_dirmap_built;\n", since="c08")

# ============ --paths and --fid2path are exclusive for a library caller too
t("paths-fid2path-excl", PFIND,
  "\t/* -printf prints its own fields, never the composed pathname */\n"
  "\tif (param->fp_format_printf_str != NULL &&\n"
  "\t    (param->fp_paths || param->fp_fid2path_mnt != NULL)) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,\n"
  "\t\t\t    \"-printf cannot be used with --paths or --fid2path\");\n"
  "\t\treturn -ENOTSUP;\n"
  "\t}\n",
  "\t/* -printf prints its own fields, never the composed pathname */\n"
  "\tif (param->fp_format_printf_str != NULL &&\n"
  "\t    (param->fp_paths || param->fp_fid2path_mnt != NULL)) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,\n"
  "\t\t\t    \"-printf cannot be used with --paths or --fid2path\");\n"
  "\t\treturn -ENOTSUP;\n"
  "\t}\n"
  "\n"
  "\t/*\n"
  "\t * Refused here and not only in lfs: a library caller setting both\n"
  "\t * gets the map on an MDT, whose answers carry the mount point that\n"
  "\t * fp_paths says they will not, and -ENOTDIR on an OST that\n"
  "\t * fp_fid2path_mnt could have named.\n"
  "\t */\n"
  "\tif (param->fp_paths && param->fp_fid2path_mnt != NULL) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -EINVAL,\n"
  "\t\t\t    \"--paths and --fid2path name objects two different ways; use one\");\n"
  "\t\treturn -EINVAL;\n"
  "\t}\n", since="c08")

# ============ the man page said every match prints as a FID
t("man-fid-sentence", FIND1,
  "A target holds no pathnames, so each match is printed as its FID.\n",
  "A target holds no pathnames, so each match is printed as its FID, unless\n"
  ".B --fid2path\n"
  "or\n"
  ".B --paths\n"
  "is given.\n", since="c08")


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
