#!/usr/bin/env python3
"""Emit b2bfix.py from two trees: b2-tip -> lower -> upper.

usage: genfix.py UPPER_WORKTREE LOWER_DIR

The fix is distributed across the stack.  Everything that works with no
in-service backend goes in from c08 (68288, where --fid2path arrives);
the target-liveness test only goes in from c22 (LU-20722, which is what
makes a target in service scannable at all), because below that commit
SCAN_BACKEND_MAX is 2 and the test could only ever be false.

Each hunk's old text is grown with context -- asymmetrically, an insertion
being anchored by the lines before it -- until it occurs exactly once in
its source tree and at most once in every commit of the stack, preferring
the anchor that matches the most commits.  The lower set is applied to each
commit before the upper set is measured against it, which is the order the
driver uses.
"""
import difflib
import os
import subprocess
import sys

WT = sys.argv[1].rstrip("/") + "/"
LOWER = sys.argv[2].rstrip("/") + "/"
BASE = "b7b1332a42a6959375c296f7a28564dcb90b2763"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "b2bfix.py")
GAP = 12

# hunks written by hand in b2bextra.py because they belong to a commit
# other than PROD or LIVE: generation would give them the wrong since, so
# a hunk whose new text carries one of these is left out here
HAND_MARKERS = ("A count no Lustre directory can have is not a count",
                "Measured by the bytes, not by a product that can")

# The 09-22 AI round landed on eight different changes, so a hunk's commit
# is not PROD or LIVE but whichever commit the finding was raised against.
# A generated hunk whose new text carries one of these takes that since.
SINCE_MARKERS = (
    ("and the third of the same family: a flag this library", "c00"),
    ("lfsr_lmm.  For a directory this is the *default* layout", "c00"),
    ("Objects may still have been left out", "c00"),
    ("sizeof(ends) / sizeof(ends[0])", "c00"),
    ("True of the path actually taken, and only because it is a shortcut",
     "c01"),
    ("a whole counter, never half of one", "c02"),
    ("an ss_size that stops inside one", "c02"),
    ("is not NULL and its", "c02"),
    ("the HSM state, the lazy", "c02"),
    ("find_get_projid() is what tests fc_path today", "c03"),
    ("A foreign LMV is a different structure at the same address", "c05"),
    ("the naming line is only printed when more than one target", "c06"),
    ("cannot read the device of %s", "c06"),
    ("if (pathstart == -1)", "c06"),
    ("mkfs.lustre's own check, through the wrapper it", "c06"),
    ("Borrowed from argv, not strdup()ed", "c06"),
    ("neither do \".\" and \"..\"", "c07"),
)


# Files whose 09-22 fixes all belong to one commit; the mixed ones stay on
# SINCE_MARKERS.  lustreapi_internal.h is c02 and not c00 because
# struct llapi_scan_stats arrives with LU-20606 and scan_stats_whole()
# cannot be written before it.
FILE_SINCE = {
    "lustre/utils/lustreapi_internal.h": "c02",
    "lustre/utils/liblustreapi_scan.c": "c02",
    "Documentation/man3/llapi_scan_namespace.3": "c02",
    "lustre/tests/llapi_scan_test.c": "c00",
    "lustre/tests/llapi_scan_changelog_test.c": "c09",
    "include/lustre/lustreapi.h": "c00",
    "lustre/utils/lfs.c": "c06",
    "lustre/utils/lfs_find_parse.c": "c06",
    "lustre/utils/libscan_zfs.c": "c07",
    "lustre/utils/liblustreapi_scan_changelog.c": "c09",
    "Documentation/man3/llapi_find_device.3": "c10",
}


def since_for(new_text, default):
    for marker, val in SINCE_MARKERS:
        if marker in new_text:
            return '"%s"' % val
    return default

# LU-20720 c21 introduces lustre_lfu.h and the record fill; the bits it
# gains are set there and read at c22, so those files carry the producer's
# since value and everything else the consumer's.
PROD_FILES = {"include/uapi/linux/lustre/lustre_lfu.h",
              "lustre/obdclass/dt_object.c",
              "lustre/include/dt_object.h",
              "lustre/lfu/lfu_ring.c",
              "Documentation/man4/lfu.ring_size.4",
              "Documentation/man4/lfu.batch.4"}

FILES = [("PFIND", "lustre/utils/liblustreapi_pfind.c"),
         ("DEV", "lustre/utils/liblustreapi_scan_device.c"),
         ("INT", "lustre/utils/lustreapi_internal.h"),
         ("KERNEL", "lustre/utils/libscan_kernel.c"),
         ("LFUREC", "lustre/utils/lustreapi_lfu_rec.h"),
         ("SPEC", "lustre.spec.in"),
         ("FIND1", "Documentation/man1/lfs-find.1"),
         ("DEV3", "Documentation/man3/llapi_scan_device.3"),
         ("CONF", "lustre/tests/conf-sanity.sh"),
         ("BACKEND", "lustre/utils/lustreapi_scan_backend.h"),
         ("LDISKFS", "lustre/utils/libscan_ldiskfs.c"),
         ("ZFS", "lustre/utils/libscan_zfs.c"),
         ("MAKEAM", "lustre/utils/Makefile.am"),
         ("LFUH", "include/uapi/linux/lustre/lustre_lfu.h"),
         ("DTOBJ", "lustre/obdclass/dt_object.c"),
         ("DTOBJH", "lustre/include/dt_object.h"),
         ("RING", "lustre/lfu/lfu_ring.c"),
         ("MAN4RS", "Documentation/man4/lfu.ring_size.4"),
         ("MAN4B", "Documentation/man4/lfu.batch.4"),
         ("LFS", "lustre/utils/lfs.c"),
         ("PARSE", "lustre/utils/lfs_find_parse.c"),
         ("SCAN", "lustre/utils/liblustreapi_scan.c"),
         ("APIH", "include/lustre/lustreapi.h"),
         ("MAN3NS", "Documentation/man3/llapi_scan_namespace.3"),
         ("SCANTEST", "lustre/tests/llapi_scan_test.c"),
         ("CLOG", "lustre/utils/liblustreapi_scan_changelog.c"),
         ("CLOGTEST", "lustre/tests/llapi_scan_changelog_test.c"),
         ("MAN3FD", "Documentation/man3/llapi_find_device.3")]


def git(*args):
    return subprocess.run(["git", "-C", WT] + list(args),
                          capture_output=True, text=True, check=True).stdout


def show(sha, path):
    r = subprocess.run(["git", "-C", WT, "show", "%s:%s" % (sha, path)],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


SHAS = git("rev-list", "--reverse", BASE + "..b1-tip").split()


def regions(a, b):
    """changed line ranges, coalesced across short runs of equal lines"""
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    out = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        if out and i1 - out[-1][1] <= GAP:
            out[-1] = (out[-1][0], i2, out[-1][2], j2)
        else:
            out.append((i1, i2, j1, j2))
    return out


PAIRS = sorted(((bb, aa) for bb in range(0, 42) for aa in range(0, 42)),
               key=lambda p: (max(p), sum(p)))


def hunks(old, new, stack):
    a, b = old.splitlines(True), new.splitlines(True)
    out = []
    for i1, i2, j1, j2 in regions(a, b):
        best = None
        for cb, ca in PAIRS:
            o = "".join(a[max(0, i1 - cb):min(len(a), i2 + ca)])
            n = "".join(b[max(0, j1 - cb):min(len(b), j2 + ca)])
            if not o or old.count(o) != 1:
                continue
            counts = [t.count(o) for t in stack]
            if any(c > 1 for c in counts):
                continue
            score = sum(1 for c in counts if c == 1)
            if best is None or score > best[0]:
                best = (score, o, n)
            if score == len(counts):
                break
        assert best is not None, (i1, i2)
        out.append((best[1], best[2]))
    return out


body = []
counts = {"lower": 0, "upper": 0}
for var, path in FILES:
    tip = show("b2-tip", path)
    # a file with no c08-level change has no lower variant: it starts from
    # the tip's own content and only the upper set touches it
    low = (open(LOWER + path).read() if os.path.exists(LOWER + path)
           else tip)
    up = open(WT + path).read()
    stack = [t for t in (show(s, path) for s in SHAS) if t is not None]

    lower_h = hunks(tip, low, stack) if tip != low else []
    # the stack as the lower set leaves it, which is what the upper set sees
    after = []
    for t in stack:
        for o, n in lower_h:
            if t.count(o) == 1:
                t = t.replace(o, n, 1)
        after.append(t)
    upper_h = hunks(low, up, after) if low != up else []

    for i, (o, n) in enumerate(lower_h):
        counts["lower"] += 1
        body.append("t(%r, %s,\n  %r,\n  %r)\n"
                    % ("%s-%d" % (var.lower(), i), var, o, n))
    default = "PROD" if path in PROD_FILES else "LIVE"
    upper_h = [(o, n) for o, n in upper_h
               if not any(m in n for m in HAND_MARKERS)]
    for i, (o, n) in enumerate(upper_h):
        counts["upper"] += 1
        body.append("t(%r, %s,\n  %r,\n  %r, since=%s)\n"
                    % ("%s-live-%d" % (var.lower(), i), var, o, n,
                       '"%s"' % FILE_SINCE[path] if path in FILE_SINCE
                       else since_for(n, default)))

HEAD = '''#!/usr/bin/env python3
"""Batch 2's second pass on 68288, 2026-09-22.  GENERATED by genfix.py.

The 09-21 re-review asked whether skipping the lookup was right for
--fid2path, which has a live mount.  Not as it stands: lmv_fid2path()
routes by FID, so an MDT object's own FID goes to the MDT being scanned --
stopped, for a device scan -- while an OST object is named by its owner's
FID on an MDT.  Measured: with the gate forced open, a --fid2path scan of a
stopped MDT0001 waited 180s and printed nothing while the console filled
with "lustre-MDT0001: not available for connect".

So the fall back is taken only where the lookup does not go to the scanned
target: the target is in service, or the record carries an owner.  And only
for a class that has a name somewhere, so an object a target keeps for
itself, a DNE agent inode and an orphan cost no ioctl to be told they have
none.

Split across the stack.  c08 (68288) gets the restructuring, the class test
and a man page that promises no MDT lookup; the liveness test waits for c22
(LU-20722), which is what first makes an in-service target scannable --
below it SCAN_BACKEND_MAX is 2 and the test could only ever be false, which
is what lreview called out.

Also here: the pp_ran assignment moved below the declarations it was
inserted above, and an EXAMPLES entry each for --fid2path and --paths.

These transforms run after b2fix's and rewrite some of its hunks, so the
list is b2fix's followed by these.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "b2-0921"))
sys.path.insert(0, os.path.join(HERE, "..", "r3-0913"))
import b2bextra  # noqa: E402
import b2fix  # noqa: E402
import r3fix  # noqa: E402

MSG = r3fix.MSG
r3fix.ORDER = ["c%02d" % i for i in range(64)]

PFIND = "lustre/utils/liblustreapi_pfind.c"
DEV = "lustre/utils/liblustreapi_scan_device.c"
INT = "lustre/utils/lustreapi_internal.h"
KERNEL = "lustre/utils/libscan_kernel.c"
LFUREC = "lustre/utils/lustreapi_lfu_rec.h"
SPEC = "lustre.spec.in"
FIND1 = "Documentation/man1/lfs-find.1"
DEV3 = "Documentation/man3/llapi_scan_device.3"
CONF = "lustre/tests/conf-sanity.sh"
BACKEND = "lustre/utils/lustreapi_scan_backend.h"
LDISKFS = "lustre/utils/libscan_ldiskfs.c"
ZFS = "lustre/utils/libscan_zfs.c"
MAKEAM = "lustre/utils/Makefile.am"
LFUH = "include/uapi/linux/lustre/lustre_lfu.h"
DTOBJ = "lustre/obdclass/dt_object.c"
DTOBJH = "lustre/include/dt_object.h"
RING = "lustre/lfu/lfu_ring.c"
MAN4RS = "Documentation/man4/lfu.ring_size.4"
MAN4B = "Documentation/man4/lfu.batch.4"
LFS = "lustre/utils/lfs.c"
PARSE = "lustre/utils/lfs_find_parse.c"
SCAN = "lustre/utils/liblustreapi_scan.c"
APIH = "include/lustre/lustreapi.h"
MAN3NS = "Documentation/man3/llapi_scan_namespace.3"
SCANTEST = "lustre/tests/llapi_scan_test.c"
CLOG = "lustre/utils/liblustreapi_scan_changelog.c"
CLOGTEST = "lustre/tests/llapi_scan_changelog_test.c"
MAN3FD = "Documentation/man3/llapi_find_device.3"

# LU-20720: the commit that introduces the wire record and fills it
PROD = "c21"
# LU-20722: the first commit with a backend that reads a target in service
LIVE = "c22"

T = list(b2fix.T)


def t(tid, path, old, new, only=None, since="c08"):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=False))


'''

TAIL = '''
# the same fixes in the spelling the commits below LU-20730 have
b2bextra.add(t, LIVE, MSG)
b2bextra.add_ring(t, PROD)
# LU-20606 c02 reads the count; LU-20611 c05 bounds the array
b2bextra.add_lmv(t, "c02", "c05")
b2bextra.add_msgfix(t, MSG)


def apply(tree, name, msg):
    saved = r3fix.T
    r3fix.T = T
    try:
        return r3fix.apply(tree, name, msg)
    finally:
        r3fix.T = saved
'''

open(OUT, "w").write(HEAD + "\n".join(body) + TAIL)
print("wrote %d lower + %d upper hunks to %s"
      % (counts["lower"], counts["upper"], OUT))
