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

---

# The fixes, 2026-09-04

Seven fixed across two commits; the three already-fixed threads replied to and
resolved on Gerrit. Series still 18 commits, 18 distinct Change-Ids, `lfs`,
`lfind` and `liblustreapi` build under `-Werror`.

## `2926fe9e` — the root is escaped, not written raw

`find_ck_escape()` maps `\` to `\\` and newline to `\n`. **Both sides escape
and the reader compares the escaped forms**, so nothing decodes — a comparison
only needs the mapping to be injective, which is also the reason backslash is
escaped.

**Proved against the unfixed build**, not just exercised. `find_cookie_read()`
and `find_cookie_write()` were lifted verbatim by regex from the tree at HEAD
and from the worktree into a standalone harness (they touch only libc), so the
control runs the *real* pre-fix text rather than a reimplementation:

| root | old | new |
|---|---|---|
| `/mnt/lustre/plain` | rc=0 | rc=0 |
| `/mnt/lustre/my data` | rc=0 | rc=0 |
| `/mnt/lustre/a`⏎`b` | **rc=-22**, "a cookie for a search under '/mnt/lustre/a'" | rc=0, anchor 42 |
| `/mnt/lustre/back\slash` | rc=0 | rc=0 |

The newline row is the reported bug reproduced: a path the caller never gave.

**The cross-version test earned a second fix.** A cookie written by the *old*
build for a backslash root is refused by the new one — expected, and harmless
since the format is unlanded — but the message read

    is a cookie for a search under '/mnt/lustre/back\slash',
      not under '/mnt/lustre/back\slash'

because it compared the escaped header text against the raw root. Both sides
now print the escaped spelling, which also keeps a newline from breaking the
line meant to name it.

## `d1c134a5` — both silent refusals now speak

`find_cookie_check()` extracted the same way, with `find_cl_oldest()` stubbed
and `mdt_count` 0 so the early refusals are reachable:

| case | old | new |
|---|---|---|
| empty name | rc=-22, **silent** | rc=-22, "--since-cookie needs the name of a file" |
| a directory *(control)* | "is not a regular file" | unchanged |
| name too long | rc=-36, **silent** | rc=-36, "too long to write beside" |

## `797f62e9`, `3eb08208` — two diagnostics

The `--resolve` refusal names both anchored spellings. The cookie wrapper is
restricted to what `fopen()` passed up: `find_cookie_read()`'s only two
`-EINVAL` returns both print their own message, enumerated at the `return`
sites, and the escape's `-ENAMETOOLONG` still gets the wrapper.

## `2a56e006`, `48df9797` — the man page

All eight `set_since()` spellings are listed, including the today-relative
forms the function's own error text offers. `-name` is tested against the
latest event **that carried a name**, with the CL_CLOSE case stated.

`groff -ww` and `checkpatch-man` show the same findings before and after — the
`register '"' not defined` warning at what is now line 1045 is pre-existing.

## `b18c8800` — the message

Four paragraphs rewritten against master rather than against a patchset: the
`local x=$(...)` split (160aa is added whole here), "the refusals the round
added", and two describing `find_decide()`'s FID printing and the
`fnmatch(NULL)` fix, both of which live in **other patches of the series**.
110 lines to 106, and the two dropped paragraphs were the cross-patch ones.

## A trap worth naming: `--amend -F` does not stage

Three of the four 68419 fixes sat **unstaged** through three `git commit
--amend -F msg` calls, which took the message and left the code behind.
`git rebase --continue` caught it only because it refused to proceed with a
dirty tree. `git show HEAD:<file> | grep -c find_ck_escape` said `0`.

**`--amend` without `-a` or a prior `git add` amends the message only** — and
the working tree still looks right, so every build and every harness run in
between passed against code that was not in the commit.
