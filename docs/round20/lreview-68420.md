# lreview on 68420 — five findings, four fixed, one held against the maintainer

**5 findings, severity medium, 8.9M tokens, $8.06.**  The overall
assessment is that "the four cases are thorough and line up with what
the implementation actually does"; the findings are prose that says
something the code does not — plus one that contradicts adilger.

## `(2)` — held, and it is a direct conflict

The finding asks for the version gates **back**:

> The body says "The gate is CLIENT_VERSION", but none of
> 160aa/160ab/160ac/160ad carries a version gate at all ... on an interop
> run with an older client the first `$LFS find $DIR/$tdir --since 8s`
> exits non-zero from getopt and the case fails rather than skips.

adilger, two hours earlier on 68095:

> client version checks are unnecessary, since the test script itself
> matches the version of the client that it runs on.

**They cannot both be acted on.**  Evidence for each, since the answer is
not obvious:

- **For adilger:** in the standard autotest setup the `lustre-tests`
  package and the client come from one build, so the gate is true by
  construction and can never skip.
- **For lreview:** `CLIENT_VERSION` is not the script's version.
  `test-framework.sh` sets it from `lustre_version_code client` →
  `lustre_build_version_node $node`, which reads the version off the
  **client host**.  So the framework can express a mismatch, and
  `sanity.sh` uses `CLIENT_VERSION` 30 times — which would be pointless
  if it always equalled the script.  The failure mode it describes is
  also real and worse than a skip: an old `lfs` exits from getopt, so
  the case **fails** rather than skipping.

**Kept adilger's answer** — he is the maintainer, he gave it on this
series, and reversing him overnight on an AI's say-so would be wrong.
But the mechanism lreview names is not imaginary, and if interop against
older clients is a configuration that actually runs, the gates belong
back.  **That is a question for the user to put to him, not for me to
settle.**

## `(1)` — the message described revisions, not the change

Three paragraphs read as a changelog between Gerrit patchsets, so against
master they describe work that is not in the diff:

- *"Four assignments in 160aa checked a status that was not lfs find's
  ... The declarations are split"* — 160aa is **added** by this patch;
  nothing is being split.
- *"lfs-find.1 no longer says --resolve 'never removes an object from the
  answer'"* — the parent has no `--resolve` entry at all.
- two more describing `liblustreapi_pfind.c`, **which this commit does
  not touch** — its diff is `lfs-find.1` and `sanity.sh` only.

Rewritten as what the patch adds.  The facts survive; the framing was
what was wrong.

## `(3)` — a comment claiming a hazard that cannot happen

160ac said the two refusals had to be tested on a fresh cookie because
`find_cookie_check()` would otherwise answer `-ESTALE` first.  Neither
can be preempted: `llapi_find_since()` tests `--since` against
`--since-cookie` in its **first block**, and the two-path case never
reaches `llapi_find_since()` at all — `lfs_find()` rejects
`pathend - pathstart > 1` before the loop that calls it.

The order is still right; the reason was invented.  Corrected to say
what is actually true.

## `(4)` — the cookie is bound to its search root, and the page did not say so

`find_cookie_write()` records the filesystem and root; `find_cookie_read()`
refuses a later run under a different one.  So reusing one cookie for a
second subtree fails — the same collision as the one-path rule, but
reached by running the command twice, which is *exactly* the use this
option exists for.  Documented, along with the not-a-regular-file
refusal.

## `(5)` — a contradiction in one sentence

> only a creation implies one — `CL_CREATE`, `CL_MKDIR`, `CL_RMDIR` and
> `CL_SOFTLINK`

`CL_RMDIR` is not a creation.  Now "only an event that implies a type
answers for it — the three creations (`CL_CREATE`, `CL_MKDIR` and
`CL_SOFTLINK`), and `CL_RMDIR`, whose target is a directory by
definition".  This is the same wording that was wrong in 68415's commit
message and fixed earlier tonight; it had been copied into the page.

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2: **56El, 160aa, 160ab, 160ac, 160ad all
PASS**, none skipped.  `groff -ww` clean apart from the pre-existing
single-backslash warning (line number shifted by two, content unchanged).
`checkpatch-man` clean apart from the standing `BASH COMPLETION`
section.  checkpatch 0 errors.  18 changes, 18 Change-Ids.
