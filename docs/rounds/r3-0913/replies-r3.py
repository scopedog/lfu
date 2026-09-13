#!/usr/bin/env python3
"""Draft the round-3 Gerrit replies (2026-09-13).  Writes one ReviewInput per
change+patchset to replies-r3/<change>-<ps>.json; posts NOTHING.

Post after the push, per change:
  ssh -p 29418 hnishida@review.whamcloud.com gerrit review <change>,<ps> --json < file
"""
import json
import os

S = os.path.dirname(os.path.abspath(__file__))
DONE = "Done."
DECLINE = object()

R = {
    # 68094 (adilger)
    "77aea866": "Done: gated on CLIENT_VERSION >= 2.17.57, so a missing binary now fails the test; 157d the same.",
    "eb27d35a": "Done: $LFS mkdir -i $((RANDOM % MDSCOUNT)); nothing in the test depends on MDT0000.",
    # 68160
    "6379d8eb": "Done: removed here; --search arrives with the ZFS backend in LU-20613.",
    "bd2794d9": "lfind.c is gone in the next patchset (lfs find --device), and the pre-pass with it.",
    # 68163
    "4fe322a2": DONE,
    "a3ac0b0d": DONE,
    "2cdfde78": "Done: narrowed to IMMUTABLE|APPEND, page and backend header with it.",
    # 68288
    "cb25d398": DONE,
    "ede43c98": DONE,
    "ae6a9326": "Done: LMV_SHARD takes 1<<47; 1<<49..52 are the changelog bits LU-20649 adds, so the set is packed.",
    "44cf4ff2": "Already fixed in the next patchset: --paths hands over the map whenever the pre-pass ran.",
    "4e556ce9": DONE,
    # 68415
    "bfa7b47a": DONE,
    "b3c1e9ac": DONE,
    "e156feaf": DONE,
    "aa575ca1": DONE,
    "617400ed": DONE,
    # 68416
    "adac49ea": DONE,
    "1f5eb08c": DONE,
    "00ea7018": DONE,
    "afc96fd0": "Done: narrowed to this function's own syscalls, with the three path-based gather opens named, here and in the page.",
    # 68417
    "a2ba1626": "Done: --since moves above --size in both sections.",
    "fff5372a": "Done, and the duplicate paragraph under the second -ENOTSUP is gone.",
    "7d9d284f": (DECLINE, "Leaving it at 0: the entries shift when a name is removed, so starting at 1 skips a name if link 0 goes mid-run. One ioctl per hardlinked candidate buys that."),
    "fd5bc71b": DONE,
    "37d1fed2": "Done: the warning names no cause now, since from --changelog on the record can be one.",
    # 68418
    "2d0b68e4": DONE,
    "b3d55630": "Done: the sentence is gone; the case cannot occur.",
    "3b37662f": DONE,
    "195af7cb": DONE,
    # 68419
    "240ce397": DONE,
    "e31be789": "Done: <cookie>.<pid>.<n>.new created O_EXCL for both the probe and the write, which keeps the umask's mode.",
    "09cfc4b1": DONE,
    "bd138920": "Done: stdout is flushed and checked before the rewrite; 160ac asserts it with /dev/full.",
    # 68420
    "3d25f00b": DONE,
    "080e9b9d": "Done in the --since patch: tm_sec is zeroed for the time-only forms.",
    "6cf9bb05": DONE,
    # 68727
    "fb139d1b": DONE,
    "0957ec61": DONE,
    "513bd9ed": DONE,
    "836aa67b": DONE,
    "8e5a951e": DONE,
}

CHANGES = [68094, 68160, 68163, 68288, 68415, 68416, 68417, 68418, 68419,
           68420, 68727]

os.makedirs(os.path.join(S, "replies-r3"), exist_ok=True)
used = set()
for c in CHANGES:
    comments = json.load(open(os.path.join(S, "c%d.json" % c)))
    by_ps = {}
    for path, lst in comments.items():
        for x in lst:
            key = x["id"][:8]
            if key not in R or x.get("in_reply_to"):
                continue
            used.add(key)
            val = R[key]
            unresolved = False
            if isinstance(val, tuple):
                unresolved, val = True, val[1]
            entry = {"in_reply_to": x["id"], "unresolved": unresolved,
                     "message": val}
            if "range" in x:
                entry["range"] = x["range"]
                entry["line"] = x["range"]["end_line"]
            elif "line" in x:
                entry["line"] = x["line"]
            by_ps.setdefault(x["patch_set"], {}).setdefault(path, []).append(entry)
    for ps, cm in by_ps.items():
        out = {"tag": "review-reply", "notify": "OWNER", "comments": cm}
        fn = os.path.join(S, "replies-r3", "%d-%d.json" % (c, ps))
        json.dump(out, open(fn, "w"), indent=1)
        print(fn, sum(len(v) for v in cm.values()))

missing = sorted(set(R) - used)
print("unmatched ids:", missing if missing else "none")
print("total replies:", len(used))
