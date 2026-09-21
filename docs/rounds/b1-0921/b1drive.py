#!/usr/bin/env python3
"""Rebuild the 26-commit stack with b1fix transforms applied to every tree.

usage: b1drive.py WORKTREE BASE TIP
Prints per-commit applied transform ids, the new tip, and which transforms
never applied.  Moves no branch.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import b1fix as fx  # noqa: E402

wt, base, tip = sys.argv[1:4]


def git(*args, env=None, inp=None):
    return subprocess.run(["git", "-C", wt] + list(args), check=True,
                          capture_output=True, text=True, env=env,
                          input=inp).stdout


shas = git("rev-list", "--reverse", "%s..%s" % (base, tip)).split()
names = ["c%02d" % i for i in range(len(shas))]

parent = git("rev-parse", base).strip()
seen = set()
for sha, name in zip(shas, names):
    git("checkout", "-q", "-f", "--detach", sha)
    msg = git("log", "-1", "--format=%B", sha)
    msg, applied = fx.apply(wt, name, msg)
    seen.update(applied)
    git("add", "-u")
    tree = git("write-tree").strip()
    env = dict(os.environ)
    for k, fmt in (("GIT_AUTHOR_NAME", "%an"), ("GIT_AUTHOR_EMAIL", "%ae"),
                   ("GIT_AUTHOR_DATE", "%ad"), ("GIT_COMMITTER_NAME", "%cn"),
                   ("GIT_COMMITTER_EMAIL", "%ce")):
        env[k] = git("log", "-1", "--format=" + fmt, "--date=raw", sha).strip()
    new = git("commit-tree", tree, "-p", parent, env=env, inp=msg).strip()
    same = git("rev-parse", sha + "^{tree}").strip() == tree
    print("%s %s -> %s %s  %s" % (name, sha[:10], new[:10],
                                  "same-tree" if same else "CHANGED",
                                  " ".join(applied)))
    parent = new

print("NEWTIP", parent)
never = [tr["id"] for tr in fx.T if tr["id"] not in seen]
print("NEVER-APPLIED", " ".join(never) if never else "none")
