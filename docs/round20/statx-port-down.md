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
