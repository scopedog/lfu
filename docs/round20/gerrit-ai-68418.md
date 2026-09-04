# 68418's AI review — both findings fixed

## `7b93ab3f` — two refusals the page did not document

The patch adds two `-EINVAL` cases and ERRORS listed neither:

    fp_resolve set with fp_changelog_mdt == NULL
    fp_changelog_mdt set, fp_resolve clear, and path below the mount

Confirmed in the tree at `liblustreapi_pfind.c:5150` and `:5227`, and on
the lab against real paths:

    lfs find /mnt/lustre/dsub --changelog all -type f
      exit 22
      under --changelog '/mnt/lustre/dsub' names the filesystem, not a
      subtree; give '/mnt/lustre', or add --resolve to search below it

    lfs find /mnt/lustre/dsub --changelog all --resolve -type f   exit 0
    lfs find /mnt/lustre --resolve -type f                        exit 4

(The first check was run against a directory 160ab had already cleaned
up and came back `exit 2` — ENOENT, not the refusal. Re-run against a
path that exists; worth recording because the wrong exit code looked
close enough to pass for the right one.)

**The reviewer's sharper point is the DESCRIPTION**, which said `@path`

> is the filesystem rather than a subtree unless `fp_resolve` is set

That reads as the bound being *widened* — as though a subtree silently
becomes the filesystem. It is not: the call fails. Now "must name the
filesystem rather than a subtree unless...", and the ERRORS entry and
the kernel-doc `Return:` block both name the two refusals, with the
reason a record carries no pathname to test a subtree against.

## `b80c4341` — the only example was the anchored form

`fp_changelog_mdt` is the mode this patch adds and the one where the
answer differs from a walk, and no example showed it. Added a second,
which also documents the subtree rule at the point a caller would trip
it:

    param.fp_changelog_mdt  = "lustre-MDT0000";

    /* the mount, not a subtree: a record carries no pathname.
     * Set param.fp_resolve to search below it, at one lookup
     * per object.
     */
    rc = llapi_find_since("/mnt/lustre", &param);

## Series position again — tenth instance

The first attempt patched ERRORS against text that does not exist at
68418: the cookie clauses ("not a regular file ... written for another
filesystem") arrive in **68419**. Written against 68418's own version
instead, and the two sets merged by hand when 68419 replayed on top —
both the cookie cases and these two now appear in one entry, in the man
page and the kernel-doc alike.

## Verification

`groff -ww` clean, `checkpatch-man` clean, checkpatch 0 errors on both
68418 and 68419. Builds under `-Werror`. Lab, ldiskfs MDSCOUNT=2:
**56El, 160aa, 160ab, 160ac, 160ad all pass.** 18 changes, 18
Change-Ids.

**This clears the open AI backlog** — every comment on every change is
triaged.
