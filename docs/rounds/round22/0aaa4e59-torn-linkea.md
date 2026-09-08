# 68159 `0aaa4e59` — a torn linkea made the object a non-match

2026-09-08, second of the seventeen. **Verified, fixed, and proved with a
lift-and-compare harness: unfixed 7 pass / 1 fail, fixed 8 / 0.**

## The claim, against the tree

`find_device_prefilter()` runs `--name` against every name in the object's
linkea. Its loop broke out when `scan_linkea_entry()` could not read entry
`i` and fell through to `return 1` — a **rejection**. Six lines above, the
`nr == 0` case calls the identical condition — "the target has no answer" —
**undecided (2)**, and says so at length in its comment.

So an object whose linkea claims three names and spells one was reported as
a non-match on a name list nobody finished reading.

## Why it is reachable, and how far

`scan_linkea_entry()` caps a count read off a device:

    if (reccount > (len - sizeof(*leh)) / sizeof(*lee))
            reccount = (len - sizeof(*leh)) / sizeof(*lee);

by the **smallest** entry that could fit. Entries are variable-length, so
`nr` can legitimately exceed the number of entries the buffer really holds,
and entry 1 then fails the `off + reclen > len` test.

Both backends deliver the whole xattr — `ext2fs_xattr_get()` allocates to
size and the ZFS side `realloc`s to it — so this needs a genuinely torn
`trusted.link`, not a large one. That is the same condition `find_lmm_fits()`
exists for on the layout side: bytes read off a target that may be in
service.

**Checked and NOT a second defect:** `nr == 1` with an unreadable entry 0
cannot reach the loop. `scan_linkea()` returns before setting
`LLAPI_SCAN_LINKEA` when entry 0 does not parse, so `nr` is 0 and the no-name
branch already answers it — which is exactly what 68159's message says it
made it do.

## The fix

The break becomes the no-name branch's shape: ask the other predicates with
a nameless record — `find_prefilter()` skips `-name` for one — and count the
object undecided only if none of them has decided it. An object `-type` has
already rejected stays rejected.

## Proved by lifting, not by retyping

A torn linkea cannot be made on a live filesystem, so this is a harness. The
functions under test are static, and a harness that retypes them tests the
copy — so `tests/lift/lift.py` **cuts `scan_linkea_entry()`,
`find_prefilter()` and `find_device_prefilter()` out of the tree's real
sources** by name and brace-matching, and the harness includes the result.
Pointing it at `git show HEAD:<file>` gives the unfixed arm from the same
harness.

| arm | unfixed | fixed |
|---|---|---|
| torn linkea, `-name zulu` | **1 (reject)** | 2 (undecided) |
| torn linkea, `-type d` rejects | 1 | 1 |
| torn linkea, `-name` matches entry 0 | 0 | 0 |
| intact linkea, no name matches | 1 | 1 |
| intact linkea, last name matches | 0 | 0 |

**The fixture is the fiddly part, and got it wrong first.** A short first
name caps `nr` to 1 and the loop under test never runs — the first harness
reported three failures that were all the fixture, not the code. The buffer
needs room for `claimed` minimum-sized entries while the entries in it are
long enough to run off the end. The first three arms now assert that premise
before anything reads into it.

## The rebase, and what it caught

Folded into 68159 with the scripted-rebase method, and it conflicted twice —
usefully. At 68159 the record's fields are still `sr_name`/`sr_linkea`; the
`lfsr_` rename is a later commit in the stack. So the hunk had to be resolved
**once in the old spelling** and **once again in the new** when the rename
commit replayed over it. Validated both ways: no `lfsr_` in 68159's file, no
stray `sr_` in the function at the tip, and the tree hash unchanged across
the message reword.
