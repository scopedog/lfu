# Porting the statx record down into the series — 2026-09-04

The statx change was implemented and lab-verified as **one commit at the
tip** (`docs/round20/statx-record.md`). Gerrit reviews each change on its
own and lreview reviews each commit in isolation, so it had to be
distributed across the ten of eighteen commits that introduce the code it
touches. Result: branch `statx-port`, 18 commits.

## The method that made it safe

Hand-editing ten rebase stops is how you get ten subtly different
versions of the same change. Instead the whole transformation was
**scripted** — `header.py` (the mask block and the struct) plus
`statxify.py` (56 exact-text replacements) — and the script was validated
before the rebase started by applying it to the pre-statx tip and
diffing against the lab-verified tree:

    applied=56 skipped=0 errors=0
    vs verified tree: 0 lines

Byte for byte. From then on the rebase could not silently drift: at each
stop the same script ran, applying whatever of itself was present at that
commit and skipping the rest.

`header.py` is commit-aware. It parses the canonical block out of the
final version and emits only the bits this commit has defined, so an
early commit gets a consistent prefix and the last gets it exactly. A
later commit that adds its own bit gets that bit renumbered into the high
half.

## Three bugs the discipline caught, none of which the compiler would

1. **An anchor that survives its own replacement.** Both insertions —
   `SCAN_DEV_ATTR_MASK` and the tests' `scan_rec_valid()` helper — keep
   their anchor text, so re-running duplicated them. `SCAN_DEV_ATTR_MASK`
   reached **three copies** and still built: C permits an identical macro
   redefinition, so `-Werror` said nothing. Fixed generally — an
   insertion (`old in new`) is skipped when the result is already there.
2. **An incomplete replacement.** The device scanner's block set the
   statx fields but never `stx_mask`, and left `sr_valid` still claiming
   the statx bits. It compiled. `check.sh`'s "sr_valid tested against a
   statx-half bit" grep is what found it.
3. **A conflict eats its own `edit` stop.** When a commit marked `edit`
   conflicts, `git rebase --continue` finalises it and moves on rather
   than stopping again — so the ldiskfs commit was committed unfixed and
   its files got fixed one commit too late. The fix is to run the
   transform *before* `--continue`, not after.

Each was found, the run aborted, the script corrected, and the rebase
restarted from scratch — three times. Restarting a scripted rebase costs
minutes; carrying a silent defect through ten commits does not.

## What was checked at the end

| | |
|---|---|
| commits | 18 (no extra, no dropped) |
| Change-Ids | all 18 **identical** to the originals |
| every commit builds in isolation | 18/18, `-Werror` |
| stale field refs / duplicate defs, per commit | none at any commit |
| tip tree vs the lab-verified tree | identical but for one comment |
| checkpatch, per patch | warning counts **identical** to before the port — zero new findings |

The one intended difference is a stale `sr_uid` reference in a struct
comment that the tip version had too; it now reads `sr_stx.stx_uid`.

## Why the lab result carries over

Everything the lab ran is byte-identical to the ported tip except that
one header comment — checked by md5 per file, not assumed. The header was
synced anyway and `llapi_scan_test` plus the full `sanity` set re-run on
the ported tree to close it.

Distributing a change across a series cannot alter the tip's behaviour if
the tip's tree is unchanged; the per-commit builds are what the
distribution actually had to earn.

## Round 21 fixes, 2026-09-04 (branch `statx-port-fixed`)

lreview on the ported series returned findings on six of eleven patches
(five runs died on a session limit, at $0.00, and were re-queued). Fixed
so far:

- **0009: a segfault.** `find_device_prefilter()`'s nameless arm called
  `find_prefilter()` with `sr_name` NULL, which reached
  `fnmatch(pattern, NULL)`. Reproduced: all 33 OST objects have a NULL
  name, `fnmatch("foo", NULL)` faults on glibc 2.34, and removing the
  guard from the tip makes `lfind --device <ost> -name foo` segfault.
  The guard existed only from 0016, seven commits later, so 0009..0015
  carried a live crash. Moved to 0009; 0016 now only extends its comment.

  The reviewer's suggested fix (pass `&named`) was **wrong**: matching ""
  returns FNM_NOMATCH, so the object would be *rejected* rather than
  counted undecided — the behaviour the code's own comment calls wrong.

- **0006/0011: `SCAN_DEV_ATTR_MASK` over-claimed.** Replaced with a
  per-backend `so_attrs_mask` carved from `so_padding`. Declared mask
  0x874 -> 0x830 with the reported attributes and immutable count
  unchanged.

- **0012: a gap in the bit sequence, mine.** `LLAPI_SCAN_OWNER` sat at
  0x0010000000000000 with `GEN` at 0x0000800000000000, leaving four bits
  unexplained until 0013 filled them. `OWNER` now takes the next bit
  (0x0001000000000000) — it belongs with the target-scanner group anyway,
  being `sr_owner_fid` from `trusted.fid` — and the event block shifts up.
  Verified: the high half doubles with no gap at **every** commit.

Plus the commit-message and man-page corrections those three implied.

**A commit was lost and recovered.** Amending on a *conflict* stop folds
the staged resolution into the previous commit and deletes the one being
applied: the series went 18 -> 17 with LU-20649 absorbed into LU-20637.
Caught by counting commits, recovered from the reflog. See
`lfu-scripted-rebase` in memory.

Re-verified after every change: 18 commits, 18 Change-Ids identical,
every commit builds in isolation, checkpatch warning counts unchanged,
`sanity` 16/16 PASS 0 FAIL 0 SKIP, `llapi_scan_test` 11/11,
`llapi_scan_device_test` 7/7, and the attrs and nameless-record guards.
