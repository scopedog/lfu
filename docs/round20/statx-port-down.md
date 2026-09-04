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

### 0012: an OST formatted `-I 256` had no owners at all

lreview's severity-medium finding, verified in the OSD source and then on
a real target. `osd_xattr_set_pfid()` takes the `LDISKFS_INODE_SIZE > 256`
early return only for larger inodes; at 256 or below it removes
`XATTR_NAME_FID` and packs the parent into the LMA as
`struct lustre_ost_attrs`, saying so with `LMAC_STRIPE_INFO`.
`lustre_loa_swab()` confirms `loa_parent_fid` is little-endian on disk
under that same flag, so it reads exactly as `scan_decode_lma()` already
reads the LMA.

`scan_owner()` now falls back to it. The LMA buffer is already in hand,
so there is no second xattr read; the length is checked against the end
of `loa_parent_fid` rather than the whole structure, because `loa_comp_*`
follow it under a different flag and are not wanted.

Measured on an OST formatted `-I 256` (`OST_FS_MKFS_OPTS="-I 256"`,
inode size confirmed 256), four files, OST offline and the MDT and client
still up so `--fid2path` could resolve:

| | owners | `lfind --fid2path` |
|---|---|---|
| before | 0 of 33 | "33 matching objects have no pathname" |
| after | 4 of 33 | all four paths printed, 29 unnamed |

The 29 are precreated objects no file owns yet, which is the right
answer. And on a default `-I 512` OST the `trusted.fid` path is
untouched: 3 files, 3 owners, 3 paths.

**Two fixture traps cost several attempts.** `llmount.sh` reformats, so
any second call throws away the `-I 256` OST and the files on it — the
whole fixture has to be one script that never remounts. And the
framework wants `OST_FS_MKFS_OPTS="-I 256"`, not `OSTOPT`: it wraps the
value in `--mkfsoptions` itself, and pre-quoting it makes `mkfs.lustre`
exit "Not enough arguments".

## Round 21 complete, 2026-09-04

All 41 findings across the eleven reviews are closed: 7 substantive
fixes (documented above and in the fix queue) plus 18 in the tail, with
one declined.

The tail's most consequential items were not the prose:

- **get_projid() logged once per object** at LLAPI_MSG_ERROR while every
  caller already reported the failure itself. Demoted to DEBUG.
- **`scan_backend_kind()`'s leading-slash arm was dead** --
  `scan_device_exists()` answers -errno for such a name first.
- **`llapi_scan_rec_path()` returned -EINVAL for an unopened mount**,
  the same errno the page tells callers to read as "this object has no
  name" -- a consumer following the page would count every record
  nameless and exit 0. Now -EBADF.
- **conf-sanity's OST refusal check passed whenever the command failed
  for any reason** -- a ZFS OST, an absent lfind, a remote OSS. Now
  gated on ldiskfs and matched against the refusal message.
- **`--ost` was refused under `--resolve` although the lookup can answer
  it**; only `--mdt` genuinely cannot, and for a different reason.
- **lfs-find.1 documented four user-visible options in the tests patch**,
  three commits after the options themselves. Moved to their own
  commits; the tip's page is byte-identical, only the placement changed.

Declined: prefixing `get_projid`/`scan_rec_dirent`/`scan_rec_gather`.
The static-library collision is real, but `lustreapi_internal.h`
already carries `get_root_path()` and friends with the same exposure,
so prefixing only ours would be an inconsistency, not a fix.

## 0008 left whole, deliberately

`LU-20611 lfs: share find's predicate parsing` is 2177 added / 1988
deleted, and **78% of the new `lfs_find_parse.c` is byte-identical to
what left `lfs.c`** -- git cannot show it as a rename because `lfs.c`
survives, so a reviewer sees two thousand lines rather than a move.
Splitting it into "move verbatim" then "the edits that make it shared"
would make it a ~200-line read.

Decided 2026-09-04 not to: the split is a review convenience, not a
correctness fix, and rewriting a commit reviewers may already have read
costs more than it saves at this point. Worth doing if the size is ever
raised in review.

For the record, the series is 17,250 insertions across 18 patches, and
rounds 20 and 21 together added 293 of them (+1.7%) -- the size is the
feature's, not the review fixes'.
