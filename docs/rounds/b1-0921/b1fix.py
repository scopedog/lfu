#!/usr/bin/env python3
"""Batch 1's lreview fixes, 2026-09-21.

Eight findings over 68158, 68159, 68160 (68163 came back clean). Three are
taken here: two commit message items and a man page clause. The one reported
as a defect -- that `%Lh` left LLAPI_SCAN_LMV out of a device scan's demand
mask -- is not one: the set it is tested against is "chiopS", whose second
character is 'h'. An instrumented build confirms lmv=1 with needs_lmv=0 for
`-printf '%Lh'` alone. The style and coverage notes are queued for the next
round, not folded here.

Transforms over each commit's tree, driven by ../r-0921/r0921drive.py's
engine; a transform applies wherever its old text is present.
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
FIND1 = "Documentation/man1/lfs-find.1"

# ===================== 68159: why an MDT object with no LMA keeps obj:ID
t("igif-msg", MSG,
  "Signed-off-by: Hiroshi Nishida <hnishida@thelustrecollective.com>",
  "An MDT object with no trusted.lma keeps obj:ID for the same kind of\n"
  "reason, from the other direction: an IGIF is the inode number and its\n"
  "generation, and the record carries no generation -- lfsr_stx.stx_ino\n"
  "is the id, and there is no field for the rest. Building one from the\n"
  "id alone would be a FID that names a different object.\n"
  "\n"
  "Signed-off-by: Hiroshi Nishida <hnishida@thelustrecollective.com>",
  only={"c05"})

# ===================== 68158: the joined call is in the loop, not a helper
t("join-msg", MSG,
  "set_time() prototype is re-indented and one call to\n"
  "llapi_lov_string_pattern() is joined onto one line. The loop moves\n"
  "with only these differences:\n"
  "- \"param.\" becomes \"param->\"\n",
  "set_time() prototype is re-indented. The loop moves with only these\n"
  "differences:\n"
  "- one call to llapi_lov_string_pattern(), under case 'L', is joined\n"
  "  onto one line\n"
  "- \"param.\" becomes \"param->\"\n",
  only={"c04"})

# ===================== 68160: a failure the command line caused ends the sweep
t("sweep-man", FIND1,
  "A target that cannot be read is reported and the others are still read,\n"
  "and the exit status is non-zero.\n",
  "A target that cannot be read is reported and the others are still read,\n"
  "and the exit status is non-zero.\n"
  "A failure the command line caused rather than the target ends the sweep:\n"
  "this build having no backend for a target's type stops it there, since\n"
  "every later target of that type would fail the same way.\n",
  since="c06")


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
