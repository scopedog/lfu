# 68157 `0a865f6a`, `7280c834`, `0f09897a` — one comment, three findings

2026-09-08, fifth through seventh of the seventeen. All three sit on the same
comment block above `find_get_projid()`, so they were settled together. Plus
`1e2c193e` on the commit message, which is the fourth and last of 68157's.

## `0a865f6a` — the code is right, the comment was wrong

The question: is the `-ENOTSUP` sentinel distinguishable from an errno
`get_projid()` can produce on its own? `ENOTSUP` and `EOPNOTSUPP` are one
number on Linux, and `get_projid()` returns `-errno` straight from
`FS_IOC_FSGETXATTR` and `LL_IOC_PROJECT` with nothing constraining it to
`ENOTTY`. All true.

**But the two cannot collide, and traced through the tree the reason is
structural, not lucky:**

- `find_get_projid()` returns `-ENOTSUP` **before** `get_projid()` is
  reached, and only when `fc_path == NULL || fc_fdp == NULL`.
- `find_decide()` decodes it as `ret == -ENOTSUP && path == NULL`.
- So `get_projid()` runs only with a path, and its `-ENOTSUP` cannot reach
  the sentinel's branch. It falls to `if (ret)` and is reported as the error
  it is — which is right.
- `fc_path != NULL` with `fc_fdp == NULL` is unreachable: every site sets the
  two together (`:3909`/`:3912` both NULL, the other three both set).

The codebase already knew this — `:4936` says "with a path in hand
find_decide() reads that as an error rather than as undecided".

**What was actually wrong is the comment**, which said the caller "decodes
them separately" as though the *value* were the discriminator. A reader
following it would think the sentinel had to be unique, and might drop the
`path == NULL` guard as redundant. It now says the context is what tells them
apart, and says why the value could not.

**Declined:** a code change. There is nothing to fix, and inventing a unique
sentinel would add a value to a path that already has an invariant.

## `7280c834` — the stranded one-liner

`/* The project id: ... */` sat immediately above a second block, leaving it
orphaned. Folded into the block's opening line.

## `0f09897a` — the schedule, and a self-reference

The paragraph pointed at LU-20611 — this patch's own ticket — for a caller
this patch does not contain, and described an ordering ("at this patch",
"arrives with") that no reader of `git log` will be able to see. Dropped; the
rewritten text says what the two values mean and leaves the schedule out.

## `1e2c193e` — the message names what it adds

`struct find_ctx` was "a context struct" and `find_get_projid()` was not
mentioned. Both are named now, with a sentence each on what they carry and
what the three answers are.

## The rebase, which went wrong twice and had to be checked

**`--grep` matched my own fixup.** `git log --grep="split cb_find_init"`
found the `fixup!` commit first, and the `edit` landed on that instead of on
68157. Any script picking a commit out of this stack by subject has to
exclude `fixup!`.

**A conflict resolution re-added the deleted text.** Folding into 68157 made
a later commit (`LU-20650 lfs: find --changelog`) conflict, and taking the
incoming side wholesale — correct for the `find_respell()` addition it
carried — brought the old one-liner back with it. The tip then had the
comment **twice**, and it built clean, so nothing would have caught it but
looking.

What caught it was comparing the finished tree against the tree the fixup had
produced before folding: `516d03c8` where `9be5b5e3` was expected. That check
is the whole point of the scripted-rebase method and it earned its keep here.
After repairing the resolution in that commit the trees match, and a sweep of
every commit in the stack finds the comment exactly once in each.
