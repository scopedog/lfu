# The ten unanswered AI threads, triaged — 2026-09-04

The 13:14 (68419) and 14:41 (68420) reviews, which landed after round 20's
triage was finished and were not looked at before the push. All ten verified
against the tree at `statx-port-fixed`.

**Seven live, three already fixed.** Only one is a code defect.

## 68419 — four, all live

### `2926fe9e` — the newline sibling of the cookie space bug

Real. `find_cookie_write()` writes the root verbatim into the header:

    fprintf(fp, "# lfs find --since-cookie for %s under %s\n", fsname, root);

and `find_cookie_read()` takes it as the rest of the line, cut at the newline:

    oldlen = strcspn(oldroot, "\n");

So `lfs find $'/mnt/lustre/a\nb' --since-cookie job.ck` records the root whole
and reads it back as `/mnt/lustre/a`. The comparison then fails for every run
after the first, naming a path the caller never gave — **the exact failure the
`%n` fix cured for spaces**, one character further out. The remainder of the
root becomes its own `fgets()` line, matches neither `sscanf` pattern, and is
dropped.

It **fails closed**, which the space bug also did, so it is not urgent; it is
the same user-visible outcome, on a rarer path.

Two ways out. **Refusing a root with a newline up front** is one line and
rejects a legal pathname. **Escaping on write and unescaping on read** makes
the format total rather than partial, which is the same direction the `%n` fix
took, and costs nothing in compatibility: the format is new in this unlanded
series, so there are no cookies in the wild to misread. Escaping is the better
fix; `\` and newline are the only two characters that need it.

Note the fsname half is safe either way — a Lustre filesystem name holds
neither a space nor a newline.

### `d1c134a5` — a silent refusal beside a talking one

Real. `find_cookie_check()` has

    if (*cookie == '\0')
            return -EINVAL;

with no message, and the `-ENAMETOOLONG` from the `snprintf()` below behaves
the same, while the "is not a regular file" case three lines down reports
itself. `lfs find --since-cookie "" /mnt/lustre` ends at
`lfs: failed for '/mnt/lustre': Invalid argument` with nothing saying the
cookie name was the problem.

### `797f62e9` — a refusal naming an option the caller did not give

Real, wording only. `--resolve` without `--changelog` is refused with

    "--resolve fills what a changelog lacks; --since already reads the object"

and `lfs find --since-cookie job.ck --resolve /mnt/lustre` reaches it. The
refusal is right — the cookie is an anchored form and verifies through the
mount — but the message is a selector short. It should name both anchored
spellings.

### `3eb08208` — one refusal reported twice, the second line wrong

Real. `find_cookie_read()` already names the reason for both of its `-EINVAL`
returns, and the caller then adds

    error: cannot read 'job.ck': Invalid argument

The file read fine; its contents were refused. The wrapper only helps for the
errno cases passed up from `fopen()`, so it should be restricted to them.

## 68420 — three live, three already fixed

### Already fixed, and the reason is the same for all three

All six sit on **PS8**, which is round 19's tree; the change is at PS9. Round
20 fixed three of them.

- **`ff135a8f`** — "nothing in the test creates a nameless record". True of
  PS8, whose 160ab had only `$LFS find $m --changelog all -name '*' > /dev/null`
  at that line. This is the same finding as `6fc1aa25` on the same change, and
  round 20's strengthened 160ab does **exactly** what this comment prescribes:
  clear the log last, append to `f1` (created before the clear, so its records
  after it are data stores with no name), create `f_new.log`, then assert
  `-name 'f_new.log'` reports it and `-name 'f1'` does not.
- **`8675182e`** — the page already says the cookie "records the filesystem
  and the root it ran under, and a later run naming a different one is refused".
- **`bb69b7c6`** — the page already names `CL_RMDIR` "whose target is a
  directory by definition" beside the three creations.

### `b18c8800` — the delta habit, eleventh instance, partly live

The "no longer says" phrasing it quotes is gone, but four paragraphs still
describe this patch against a patchset rather than against master:

- *"160aa declares its locals apart from the assignments"* — 160aa is added
  whole here, so there is nothing being split;
- *"The refusals the round added"* — "the round" is a patchset concept;
- *"find_decide() counted the object as having no pathname instead of printing
  its FID"* and *"that used to reach fnmatch() with NULL"* — both changes live
  in **other patches of the series**, so grepping `git log` for them lands here
  and finds nothing.

Its length point is fair too: ~110 lines for a patch adding four sanity cases
and a man-page section.

### `2a56e006` — the page lists two of eight timestamp spellings

Real. `set_since()`'s table is

    "@%s", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d",
    "%H:%M:%S", "%H:%M"

and `lfs-find.1` lists `2026-08-25` and `2026-08-25T18:00` only. The space
separator, the with-seconds forms and the two today-relative forms are all
accepted and undocumented — and **the function's own error text offers
`18:00 for today`**, so a reader who trips the error is pointed at a spelling
the page does not have.

### `48df9797` — "latest event" is one word short

Real. The page says `-name` is tested against the name "the object's **latest**
event carried". `scan_cl_absorb()` replaces `co_name` only when
`cr_namelen != 0`, so a file created as `f` and then written and closed keeps
`f` and still matches `-name f`, though its latest event is a `CL_CLOSE` that
carried nothing. It is the latest event **that carried a name**. The hardlink
example below it follows from the narrower statement unchanged.

## Disposition

| thread | kind | state |
|---|---|---|
| 68419 `2926fe9e` | defect (fails closed) | fix — escape the root |
| 68419 `d1c134a5` | diagnostic | fix |
| 68419 `797f62e9` | wording | fix |
| 68419 `3eb08208` | diagnostic | fix |
| 68420 `b18c8800` | commit message | fix |
| 68420 `2a56e006` | man page | fix |
| 68420 `48df9797` | man page | fix |
| 68420 `ff135a8f` | test | already fixed in PS9 |
| 68420 `8675182e` | man page | already fixed |
| 68420 `bb69b7c6` | man page | already fixed |
