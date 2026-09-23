#!/usr/bin/env python3
"""Rebuild the 26-commit stack with b2fix transforms applied to every tree.

usage: b2drive.py WORKTREE BASE TIP [PREV_TIP]
Prints per-commit applied transform ids, the new tip, and which transforms
never applied.  Moves no branch.

PREV_TIP is the last drive's tip, normally what is on Gerrit.  A commit
whose tree, parent and message match the one at its position there is
reused as it is, so an unchanged change gets no new patchset.  The
committer date is also pinned to the source commit's, so two drives of the
same input give the same SHAs.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import b2bfix as fx  # noqa: E402

wt, base, tip = sys.argv[1:4]
prev_tip = sys.argv[4] if len(sys.argv) > 4 else None


def git(*args, env=None, inp=None):
    return subprocess.run(["git", "-C", wt] + list(args), check=True,
                          capture_output=True, text=True, env=env,
                          input=inp).stdout


shas = git("rev-list", "--reverse", "%s..%s" % (base, tip)).split()
names = ["c%02d" % i for i in range(len(shas))]

prev = []
if prev_tip is not None:
    prev = git("rev-list", "--reverse", "%s..%s" % (base, prev_tip)).split()

parent = git("rev-parse", base).strip()
seen = set()
for i, (sha, name) in enumerate(zip(shas, names)):
    git("checkout", "-q", "-f", "--detach", sha)
    msg = git("log", "-1", "--format=%B", sha)
    msg, applied = fx.apply(wt, name, msg)
    seen.update(applied)
    git("add", "-u")
    tree = git("write-tree").strip()
    env = dict(os.environ)
    for k, fmt in (("GIT_AUTHOR_NAME", "%an"), ("GIT_AUTHOR_EMAIL", "%ae"),
                   ("GIT_AUTHOR_DATE", "%ad"), ("GIT_COMMITTER_NAME", "%cn"),
                   ("GIT_COMMITTER_EMAIL", "%ce"),
                   ("GIT_COMMITTER_DATE", "%cd")):
        env[k] = git("log", "-1", "--format=" + fmt, "--date=raw", sha).strip()
    new = None
    reused = False
    if i < len(prev):
        p = prev[i]
        if (git("rev-parse", p + "^{tree}").strip() == tree and
                git("rev-parse", p + "^").strip() == parent and
                git("log", "-1", "--format=%B", p).rstrip() == msg.rstrip()):
            new = p
            reused = True
    if new is None:
        new = git("commit-tree", tree, "-p", parent, env=env,
                  inp=msg).strip()
    same = git("rev-parse", sha + "^{tree}").strip() == tree
    print("%s %s -> %s %s%s  %s" % (name, sha[:10], new[:10],
                                  "same-tree" if same else "CHANGED",
                                  " REUSED" if reused else "",
                                  " ".join(applied)))
    parent = new

print("NEWTIP", parent)
never = [tr["id"] for tr in fx.T if tr["id"] not in seen]
print("NEVER-APPLIED", " ".join(never) if never else "none")
