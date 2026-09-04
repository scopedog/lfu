# adilger's review of 68095 — approval, and two on the test

**2026-09-03 22:46**, continuing through the series after 68094.

## The patchset-level comment is the news

> This looks very reasonable, and correctly extracts the code from
> `lfs find` instead of duplicating it.

The first outright approval from the maintainer on this series, and on
the change that carries the `cb_find_init()` restructure.  Worth
recording against the 15 comments on 68094: his objections there are to
the **record and parameter API**, not to the refactor.

## `2a3ed73d` — the client version gate is dead code

> client version checks are unnecessary, since the test script itself
> matches the version of the client that it runs on.

He is right, and it is worth stating why rather than just complying: the
gate was

    (( $CLIENT_VERSION >= $(version_code 2.17.57) )) || skip ...

and the tree **is** 2.17.57, so it can never skip.  The script ships
with the client build, so a `>=` client gate for a client-side feature
is a condition that is true by construction.

Removed from all five of our tests: **56El** in 68095 and **160aa,
160ab, 160ac, 160ad** in 68420.  For consistency, also from **160z** in
68414 (`lustre-lu20648`), whose `MDS1_VERSION >= 2.17.50` gate **stays**
— changelog filtering is a server feature and that one can genuinely
fail.

This supersedes the earlier lreview finding `fcca55ff`, which said these
should gate on the client rather than the MDS.  It was right that the
MDS gate was wrong; the maintainer's answer is that there should be no
gate at all.  Both agree the MDS version was the wrong question.

Convention checked before acting: `sanity.sh` carries 30 `CLIENT_VERSION`
uses against 309 `MDS1_VERSION` ones, so client gates are the rare case
in this file, not the norm.

Verified on the lab that all five now **run** rather than skip — the
failure mode of a wrong gate is a silent skip, which looks like a pass.

## `f5f45a48` — declined, and the test now says why

> rather than mounting a new filesystem (and having to clean it up), it
> could just create the test directory and files in `$TMP/$tdir`, unless
> the goal is that this is a subdirectory inside the Lustre filesystem?

**That is exactly the goal**, and his own question anticipates it.  56El
covers a walk that starts on Lustre and crosses off it: 68095 is the
change that made the walk descend into such a subtree instead of losing
it.  Files in `$TMP` are not under `$DIR`, so `lfs find $dir` would never
reach them and the case would not be exercised at all.

Not changed — but the question is a fair one to have to ask, so the test
now answers it in place:

    # under $dir on purpose, and not in $TMP: the case is a walk that
    # starts on Lustre and crosses off it, so the subtree has to be
    # reachable from a Lustre path.  A tmpfs is the cheapest filesystem
    # that is certainly not Lustre and needs no device.

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2: **56El, 160aa, 160ab, 160ac, 160ad all
PASS**, none skipped.  checkpatch 0 errors on 68095 and 68414; 68420
carries only its standing `Test-Parameters:` line.  18 changes, 18
Change-Ids; 68414's Change-Id unchanged.
