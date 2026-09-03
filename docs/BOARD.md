# The LFU board — one page

Every ticket and Gerrit id in play, and the ones that are *not* ours. Regenerate
the top table with `tests/gerrit-poll/gpoll.py`'s query; last refreshed
**2026-09-02**.

## Ours: twenty-one changes in review (round 19 pushed 2026-09-03)

Stack order (bottom first). `PS` is the current patch set.

| Ticket | Gerrit | PS | Subject | Votes |
|---|---|---|---|---|
| LU-4315 | [68616](https://review.whamcloud.com/c/fs/lustre-release/+/68616) | 1 | contrib: let SEE ALSO carry subsections | new |
| LU-19982 | [68617](https://review.whamcloud.com/c/fs/lustre-release/+/68617) | 1 | doc: fix lustreapi.7 SEE ALSO order and AVAILABILITY | new |
| LU-20624 | [68231](https://review.whamcloud.com/c/fs/lustre-release/+/68231) | 5 | utils: fix stale fd in cb_get_dirstripe | jenkins+1, maloo−1 |
| LU-20603 | [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | 16 | llapi: namespace scanner API | jenkins+1, maloo−1 |
| LU-20605 | [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | 17 | llapi: build find on the scan record | jenkins+1 |
| LU-20606 | [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | 16 | llapi: scan an ldiskfs target directly | jenkins+1 |
| LU-20611 | [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | 16 | llapi: split cb_find_init's decider out | jenkins+1 |
| LU-20611 | [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | 16 | lfs: share find's predicate parsing | jenkins+1 |
| LU-20611 | [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | 16 | llapi: run find over a device scan | jenkins+1 |
| LU-20611 | [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | 17 | utils: lfind, find over a target | jenkins+1 |
| LU-20613 | [68163](https://review.whamcloud.com/c/fs/lustre-release/+/68163) | 15 | llapi: ZFS backend for llapi_scan_device | jenkins+1 |
| LU-20637 | [68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288) | 10 | llapi: name a device scan's objects | jenkins+1 |
| LU-20643 | [68340](https://review.whamcloud.com/c/fs/lustre-release/+/68340) | 3 | utils: clear stale lmd fields on reuse | jenkins+1, maloo−1 |
| LU-20647 | [68413](https://review.whamcloud.com/c/fs/lustre-release/+/68413) | 6 | mdd: look up a changelog user of either record type | jenkins+1 |
| LU-20648 | [68414](https://review.whamcloud.com/c/fs/lustre-release/+/68414) | 6 | mdc: fix changelog mask composition | jenkins+1 |
| LU-20649 | [68415](https://review.whamcloud.com/c/fs/lustre-release/+/68415) | 8 | llapi: a changelog as an Object Stream | jenkins+1 |
| LU-20650 | [68416](https://review.whamcloud.com/c/fs/lustre-release/+/68416) | 8 | llapi: fill a scan record for one FID | jenkins+1 |
| LU-20650 | [68417](https://review.whamcloud.com/c/fs/lustre-release/+/68417) | 8 | lfs: find --since, from the changelog | jenkins+1 |
| LU-20650 | [68418](https://review.whamcloud.com/c/fs/lustre-release/+/68418) | 8 | lfs: find --changelog, the log as source | jenkins+1 |
| LU-20650 | [68419](https://review.whamcloud.com/c/fs/lustre-release/+/68419) | 8 | lfs: find --since-cookie, per-MDT anchor | jenkins+1 |
| LU-20650 | [68420](https://review.whamcloud.com/c/fs/lustre-release/+/68420) | 8 | tests: sanity cases for find's changelog flags | jenkins+1 |

### The two preparatory changes (2026-09-03)

Round 18 adds a `Namespace Scanning` subsection to
`Documentation/man7/lustreapi.7`, which makes checkpatch audit the whole page:
**46 pre-existing findings**, so 68094, 68156, 68288, 68415 and 68416 showed
~48 each where they showed 1–2.

**42 of the 46 are checkpatch disagreeing with a landed upstream change.**
`e558bbedc1 LU-19982 doc: Group lustreapi.7 functions by category` (Malkeet
Singh, 2026-05-14, reviewed by Drokin, Dilger and Kansal) grouped the SEE ALSO
references into `.SS` subsections. `contrib/scripts/checkpatch-man.pl`'s
SEE ALSO checker accepts only a flat sorted run of `.BR page (N),` lines, so
every subsection's description line and every `.PP` is reported as a malformed
reference — 28 + 14 warnings. Flattening the page to satisfy it would revert
LU-19982, so the fix is to the tool.

| Count | Finding | Real? |
|---|---|---|
| 28 | `SEE ALSO lines must be of the following form` | No — every `.SS` prose line and `.PP` |
| 14 | `'.PP' should end with ','` | No — same cause |
| 2 | sort order (`llapi_pcc_state_get`, `llapi_fid_hash`) | **Yes** |
| 1+1 | AVAILABILITY names `.B lustre (8)` | **Yes** |
| 1 | ERROR: missing `release X.X.0`/`commit` for SUBJECT | Left — the page dates itself to 0.9.1 |
| 1 | CHECK: non-standard manual section | Left — the user's standing call |

After both changes `lustreapi.7` goes from `1 errors, 42 warnings, 4 checks`
to `1 errors, 0 warnings, 2 checks`. Every man page under `Documentation` was
checked before and after: **378 pages, and `lustreapi.7` is the only one whose
count changes.**

### Round 19, unpushed (2026-09-03)

`lreview` — the Gerrit AI review run locally, before pushing — found three
defects on **68419**. All three verified against the tree, none already fixed,
none noise. Fixed, with a before/after measurement on the lab for each:

| Finding | Consequence before the fix |
|---|---|
| The cookie header's root read with `%s` | A search root with a space read back truncated, so **every run after the first exited `-EINVAL`**, naming a path the caller never gave |
| `%4x` on the MDT number | `-MDT0000_UUID` and `-MDT00001` **anchored MDT0000** at an index never written for it, suppressing the whole answer at exit 0 |
| `-ESTALE` absent from `llapi_find_since.3` | The error the option is built around, missing from the only place an API caller would look |

A fourth fell out of the regression arms: the old guard
`if (*num == '-' || *num == '+')` inspects only `num[0]`, so
`lustre-MDT000-1` put the sign at index 3 and `%4x` read `000` — the exact
case that guard's comment said it stopped.

`tests/lab-r18/05-arms-cookie.sh` pins all of it and is itself validated
against a build without the fix, where it fails 5 of 8 while the one arm that
must pass either way still passes. **The discriminator is
`liblustreapi.so`, not `lfs`** — `find_cookie_read()` is in the library.

The lab's own `-name` asymmetry is **documented rather than fixed** (the
user's call, 2026-09-03): the log is coalesced to one record per object, so
the only name `-name` can match is the object's *latest* event's, and the
pathname printed is its *first* name. `llapi_scan_changelog.3` now says which
event's fields the coalesced record carries, and `lfs-find.1` says which name
`-name` tests. No behaviour change.

Three commits changed: **68415**, **68419**, **68420**. Every other commit is
byte-identical by `git range-diff`, and no checkpatch count moved.

### 68156's review (2026-09-03) — five findings, five real, five fixed

10.4M tokens, $9.81, 27m38s. Every one verified against the tree first.

| # | Finding | Fix |
|---|---|---|
| 1 | The device scanner stamped `trusted.lmv` — a directory's **actual** stripe — with `LMV_USER_MAGIC`, which the tree uses for a **default** LMV (`cb_get_dirstripe()` sets it exactly when `fp_get_default_lmv` is asked for). `llite/dir.c:2274` fills `LMV_MAGIC_V1`, so the two scanners gave one striped directory two values in the same field — against `sr_lmv`'s promise that it means one thing whichever scanner filled it | `LMV_MAGIC_V1` |
| 2 | `sb_dl_handle` assigned after `dlopen()` and never read; both error paths use the local handle, and 68163 only carries it as context | field removed |
| 3 | `LLAPI_SCAN_PARENT` never named in `llapi_scan_device.3` — and `sr_parent_fid` was written unconditionally while `sr_owner_fid` twenty lines on memsets itself when insane | memset + a `.TP` |
| 4 | Missing words in the `ss_class` sentence in `lustreapi.h` | reworded to match the man page |
| 5 | The `llapi_test_utils` `run_test_tbl()` split unexplained in the message | sentence added |

**Finding 1 is a contract broken, not a wrong answer observed** —
`lmv_dump_user_lmm()` is reached only from the `getstripe`/`getdirstripe`
walk callbacks (`liblustreapi.c:3597`, `:3688`), never from a scan record. It
is what *would* break: the magic decides its `(Default)` prefix and which
fields a bare `-v` shows. Stated that way in the commit message rather than
claiming user-visible breakage.

Verified: `-Werror` clean, every checkpatch count at baseline, `sanity`
56El/157c/160aa–ad/160y/160z **PASS ×2, zero skips**, both arms suites
**8/8 and 14/14**, and the final tree diff carries only the intended changes
— the extra commit `range-diff` flagged was context-only, checked rather
than assumed.

### conf-sanity test_168, --paths (2026-09-03)

`--paths` had **no test at all** — 166 and 167 both exercise only
`--fid2path` — which is what 68288's review flagged. `test_168` scans an MDT
in service **with no mount given**, the case a filesystem whose only MDT is
the target has to be named in, and asserts one path per object rather than one
per name (20 objects from 21 names), the hardlinked object once, no FID where
a path was asked for, and **no mount point in the answer** — root-relative
being what separates `--paths` from `--fid2path`, and a mounted prefix meaning
the wrong composer ran. Plus both refusals: on an OST, and together with
`--fid2path`.

**`PASS 168 (11s)`**, and both refusals verified to fire for their own reasons
rather than incidentally. The `--paths`+`--fid2path` arm doubles as end-to-end
cover for finding (5)'s fix: it now prints the usage block and exits 1, where
before it exited 4 in silence.

**Reviews still owed:** 68418 and 68288 both died on API overload (ten
retries at `529`, zero tokens); an earlier 68418 attempt died at a `500`
after $2.77. 68156 is running. Run `lreview` **one at a time** — three
concurrently is self-inflicted contention.

### The push, 2026-09-03

Round 19 went to Gerrit with the user's word. **Two new changes — 68616
(LU-4315) and 68617 (LU-19982)** — and new patchsets for the sixteen in the
main chain. Every existing Change-Id was mapped to its change before pushing;
a lost one would have created a duplicate instead of a patchset.

Checked first, and worth checking: **68415's parent on Gerrit is 68288**, and
68340/68413/68414 hang off 65345 outside the main chain, so `r16-work`
matched the chain exactly and nothing was reparented. 65345 is MERGED and is
our base commit. Our base is an ancestor of `review/master`, which has moved
on — not rebased onto it, per [[gerrit-etiquette]].

**68413 was deliberately NOT pushed.** Its `lu-20647-r18` branch is
**functionally identical to PS6** — the code matches once comments are
stripped, the only differences being two relocated comments — and its commit
message is 44 lines against PS6's 60. Pushing would spend a patchset
(≈30 test sessions, ≈150 machine-hours) to shuffle two comments and *lose*
16 lines of explanation. PS6 is the better revision and stands.

**As of 2026-09-02 17:48 every one of the nineteen carries `maloo Verified-1`**
— all of them the LU-20598 `sanity-sec` roll-up, not a defect of ours. That
now blocks landing: the Maloo annotation has stopped being free and needs the
user's login. The vote arrives with a message that says *"Passed enforced test
review-dne-part-3"*, so read the -1 against the session list and not against
the sentence attached to it. `adilger` left the series' only human vote, `Code-Review+1` on 68413 PS2,
now stale at PS6.

## Not ours: other people's tickets that show up in our CI

| Ticket | What it is | Where we see it |
|---|---|---|
| **LU-20598** | `sanity-sec` fails in `review-dne-selinux-ssk-part-2` | Every change, deterministically. The only thing producing `maloo −1` on the series. 26 of 37 other owners' changes hit it too |
| **LU-20523** | MDS LBUG in `tgt_grant_sanity_check()` when the ZFS MDT quota is lowered below the outstanding client grant — `sanity` **805** and **807a**. Open, filed 2026-07-25 by Oleg Drokin, affects 2.17.0 / 2.15.8 | The `%% CRASHED %%` sessions in `review-dne-zfs-part-1`. Read off 68418's crash dump 2026-09-02 |
| **LU-17857** | `sanityn test_cleanup: Autotest time out` | `review-dne-*-part-5`, six of our changes so far |
| **LU-19027** | `sanity` 271d/271f `-1 resend occured` | Data-on-MDT read-on-open |

Plus the unticketed regulars with Janitor 30-day rates in the hundreds:
`sanity-pcc` 1c/1d, `recovery-small` 155, `sanity-lfsck` 18c, `sanity-hsm` 12u,
`sanity-quota` 86, `sanity` 45 and 311. See the `lfu-autotest-known-noise`
memory for the evidence behind each.

## Ours to file, after the series converges

**osd-zfs FORTIFY_SOURCE warning, unticketed.** Searched 2026-09-02: no
matching LU exists (`osd_index_it_key` returns only LU-13769 and LU-15827;
"field-spanning write" returns only LU-17545 and LU-16509, both unrelated).

```
memcpy: detected field-spanning write (size 16) of single field "&it->ozi_key"
        at lustre/osd-zfs/osd_index.c:1932 (size 8)
  osd_index_it_key <- lfsck_namespace_double_scan_one_trace_file <- lfsck_assistant_engine
```

`ozi_key` is a `__u64`; the key is 16 bytes, `sizeof(struct lu_fid)`, because
the lfsck namespace trace files are FID-keyed. **Not memory corruption** —
`ozi_key` shares a union with `ozi_name[MAXNAMELEN]`, so the write lands in
allocated space and FORTIFY is objecting to the type, not the extent. It fires
on every ZFS + lfsck-namespace run. One-line fix: copy through the union member
rather than through `&ozi_key`.

Deliberately **not filed yet**: it is outside our series, and a second
unrelated ticket in front of the same reviewers while nineteen changes are in
review costs more than it buys.
