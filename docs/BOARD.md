# The LFU board — one page

Every ticket and Gerrit id in play, and the ones that are *not* ours. Regenerate
the top table with `tests/gerrit-poll/gpoll.py`'s query; last refreshed
**2026-09-06**.

## The find-device page claimed a lookup per object (2026-09-06)

68288 `91527192`, verified in all three parts and fixed: the NOTES said each
FID is resolved through the mount by `llapi_scan_rec_path(3)`, which for an
MDT target never happens — the map composes and there is no fallback, and the
mount is the prefix and the fsname check. `lfind(8)` had it right all along.
`fp_paths` was undocumented and `-ENOTDIR`/`-EXDEV` were missing from ERRORS;
both fixed. `docs/rounds/round22/91527192-find-device-page.md`.

## A striped directory's shard became a path component (2026-09-06)

68288 `af2ef8f0`, the evening round's other defect: verified, reproduced and
fixed. `lfind --paths` printed `/shardtest/[0x200000400:0x2:0x0]:0/f1` where
the filesystem has `/shardtest/f1`, and `--fid2path` reached it too, there
being no fallback from the map. Fixed with a new record bit
`LLAPI_SCAN_LMV_SHARD` and a nameless map entry the walk steps through, which
is the shape `mdt_path_current()` already has.
`docs/rounds/round22/af2ef8f0-dir-shards.md`.

**Left for its own patch:** `-type d` still prints the shard as an object of
its own. The principled fix is an `LLAPI_SCAN_CLS_*` class, which changes what
a scan delivers by default. **The comment's repro line is wrong** — `-c 1`
makes a plain directory here, `-c 2` is what makes shards.

## 68415's other four AI threads, all fixed (2026-09-06)

`9e911017` (a comment claiming "what every event answers for", with four
counterexamples in `scan_cl_absorb()`), `6cd44cc3` (`O_NOFOLLOW` is inert under
`open_by_handle_at()`; `O_PATH` is what makes a symlink openable), `60b237d1`
(the page cited a private symbol; it now uses the sibling's prose) and
`62e0c7ba` (the test ran outside `TEST_REGISTER`/`run_tests()` — converted, so
each case is forked and `-e`/`-o` select).

While in the test, **the DNE trap from the lab is now diagnosed rather than
suffered**: it says `... is on MDT0001, not the MDT0000 that -m names` instead
of failing with "no CL_RENAME in the stream". Run on the VM: six cases pass
forked, `-o`/`-e` select, the guard fires.
`docs/rounds/round22/68415-remaining-threads.md`.

## A filtered record stalled `_CLEAR` (2026-09-06)

68415 `e21128ea`, the second defect of the evening AI round, verified and
fixed: `sc_filter` rejecting a record left `sl_accepted` behind, so a consumer
filtering with `LLAPI_SCAN_CL_F_CLEAR` never cleared and the registered user's
backlog grew without bound. One assignment, plus the man-page half the comment
did not ask for — `_CLEAR` no longer means "never ahead of `cb`" but "never
ahead of the consumer", which widens what clearing may destroy.
`docs/rounds/round22/e21128ea-filter-clear.md`. No lab run (the user's call);
clearing needs a changelog user, which needs 68413/68414 in the same tree.

## `--since` prints each path once: LLAPI_SCAN_CL_F_ONCE (2026-09-06)

68417 `cda04667`, the thread that was **the user's call**, settled and built:
a new library flag on 68415, used by 68417/68418/68419. Coalescing collapses
an object only within `sc_min_age`, so `--since 30d` printed a daily-written
file ~30 times. The set is 16 bytes a slot against a `scan_dirmap` this series
already ships at 288, and it saves the duplicate `llapi_scan_fid()`.

Reviewing the diff caught the first version turning a duplicate into a
**miss** — a pre-window burst marked the object delivered and suppressed the
one inside the window. The `--since` window cut and the cookie anchor both
moved into `sc_filter`, ahead of the suppression.
`docs/rounds/round22/cda04667-once-flag.md`.

**RUN on the local VM and green** (`docs/rounds/round22/lab-once-flag.md`):
100010 objects between one file's two events force the eviction the 600s
`sc_min_age` cannot be faked into, and the paired arms on one build of the
modules give **unfixed 2 lines, fixed 1**, with the run's own count of changed
objects going 100022 -> 100021 — the duplicate lookup is not paid either. The
library's test5 proves its premise first (2 arrivals without the flag,
`sc_max_cached=1`) and then one with it. `sanity` 56El, 157c, 160aa-160ad
**PASS x2, zero skips**.

## New patch: the trailing-slash trim (2026-09-06)

`LU-20605 llapi: trim a start point's trailing slashes` — `02d913438a`, on
top of the stack, **under LU-20605 rather than a new ticket**. `-name`
against a start point spelled with a slash: 1 of 3 patterns correct before,
3 of 3 after. `docs/rounds/round22/lfs-find-trailing-slash.md`.

Settled against a **stock lfs built from the series base**: the doubled
path separator is upstream and not ours (ticket held, see the memory), and
68095's `-name` change was **not a regression** — stock matches nothing at
all for such a start point.

## The AI review backlog is empty (2026-09-06)

**34 replies posted; 40 open AI threads down to 7**, and all seven are
deliberate, each with a reply saying why — 68095 `937bc492`, 68156
`ab78d3de` (adilger's last word), 68159 `e6fb45c4`, 68288 `8d405103`,
68417 `122b863e` and `cda04667` (**the user's call**), 68420 `39df2275`.

Every fix from rounds 20–22 is unpushed, so the replies say **"Lands in the
next patchset"** rather than `Done.` — a `Done.` on an unpushed fix would be
a false claim. "Already fixed in a later patchset" is used only where the
current patchset genuinely carries it (68340, 68413 ps1, 68414).

## Round 22, part 2: 68094 and 68095's first AI review (2026-09-06)

Seven threads, **the first the Gerrit AI has posted on ps17/ps18**. All seven
verified, all seven real; five fixed, two answered in the message.
`docs/rounds/round22/ai-threads-68094-68095.md`.

- **`6813c461`** — `sp_want = STATX_INO` returned `stx_ino=0` with the bit
  clear, though the public header promises the whole low half and the ioctl
  fills it. `STATX_INO|STATX_SIZE` answered the same field correctly, which
  is what makes it a defect. Measured on the lab; fixed in the MDT mask.
- **`440a87f7`** — an object with **no** project id matched neither
  `--projid 0` nor `! --projid 0`, against the arm's own comment. Reproduced
  on the lab (the symlink was in neither answer, now in exactly one).
- `0397b439` the `lmd_fid` clear moved out of the shared helper; `7611a1a0`
  `LLAPI_MSG_DEBUG` quiets nothing (comment + message corrected, behaviour
  left); `d191189e` comment moved back to its function; `36c4ca49` and
  `937bc492` answered in the commit message — the latter with a measured
  three-way comparison showing new, old and `find(1)` all differ.

**Rebase hazard, met again:** `LU-20611` *moves* the project-id block, the
conflict resolution took the incoming side, and the fix committed one patch
earlier was dropped from every commit after it. Caught by grepping the
finished tree — see [[lfu-scripted-rebase]].

Verified: `range-diff` shows three commits changed in content (two more
differ only in context); `-Werror` clean; checkpatch 0/0; `sanity` 56El,
157c, 160aa–160ad **PASS ×2, zero skips**; rounds 19/21 arms still 8/0 and
17/0.

## The lab round 21 owed: RUN and green (2026-09-06)

68419/68420's seven fixes, paired A/B against the pushed PS9 build:
**11/6 unfixed → 17/0 fixed**, round 19's arms 8/0 on both, `sanity`
160aa–160ad PASS ×2 with zero skips. The gate on pushing rounds 20/21 is
therefore **cleared**. `docs/rounds/round22/lab-68419-68420.md`.

Two corrections the lab forced, which the Gerrit replies must carry rather
than a bare `Done.`: **`797f62e9`'s repro is wrong** (the shared parser
refuses first, so only a direct `llapi_find_since()` caller reaches the
message the fix changed), and **`d1c134a5`'s branch** needs a deep 4092–4095
path, not one long component.

## Round 22, unpushed (2026-09-06)

The five new AI threads on **68616** and **68617** — the reviews that landed
on the current patchsets after round 21's push. All five verified, all five
fixed; `docs/rounds/round22/ai-threads-68616-68617.md`.

- 68616 `e2548ac1` — a `.SS` closed the run for ordering but not for the
  trailing-comma test, so a run ending `.BR aaa (3),` passed silently
- 68616 `eef5b8a3` — `.P` and `.LP` are exact synonyms of `.PP` in man(7),
  and a `.P` was reported as a malformed reference
- 68616 `dd3a74a3` — a capturing group left `$1` holding `l`/`ustre`
- 68617 `94839f00`, `dc2321c4` — two commit-message counts measured off the
  wrong page state (`5 checks` is 4; the `release`→`commit` baseline is
  `1/0/2`, not `1/2/4`)

389 pages swept before and after: not one count moved. checkpatch clean.

**The unpushed pile is now three rounds deep**: round 20 on 68340/68413/
68414, round 21's seven on 68419/68420 (which still owe a lab run), and
these five.

## Ours: twenty-one changes in review (round 21 pushed 2026-09-04)

Stack order (bottom first). `PS` is the current patch set.

| Ticket | Gerrit | PS | Subject | Votes |
|---|---|---|---|---|
| LU-4315 | [68616](https://review.whamcloud.com/c/fs/lustre-release/+/68616) | 3 | contrib: let SEE ALSO carry subsections | jenkins+1, maloo+1 |
| LU-19982 | [68617](https://review.whamcloud.com/c/fs/lustre-release/+/68617) | 2 | doc: fix lustreapi.7 SEE ALSO order and AVAILABILITY | jenkins+1, maloo+1 |
| LU-20624 | [68231](https://review.whamcloud.com/c/fs/lustre-release/+/68231) | 6 | utils: fix stale fd in cb_get_dirstripe | jenkins+1, **adilger+1** |
| LU-20603 | [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | 17 | llapi: namespace scanner API | jenkins+1 |
| LU-20605 | [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | 18 | llapi: build find on the scan record | jenkins+1 |
| LU-20606 | [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | 17 | llapi: scan an ldiskfs target directly | jenkins+1 |
| LU-20611 | [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | 17 | llapi: split cb_find_init's decider out | jenkins+1 |
| LU-20611 | [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | 17 | lfs: share find's predicate parsing | jenkins+1 |
| LU-20611 | [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | 17 | llapi: run find over a device scan | jenkins+1 |
| LU-20611 | [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | 18 | utils: lfind, find over a target | jenkins+1 |
| LU-20613 | [68163](https://review.whamcloud.com/c/fs/lustre-release/+/68163) | 16 | llapi: ZFS backend for llapi_scan_device | jenkins+1 |
| LU-20637 | [68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288) | 11 | llapi: name a device scan's objects | jenkins+1, janitor−1 |
| LU-20643 | [68340](https://review.whamcloud.com/c/fs/lustre-release/+/68340) | 3 | utils: clear stale lmd fields on reuse | jenkins+1, maloo−1 |
| LU-20647 | [68413](https://review.whamcloud.com/c/fs/lustre-release/+/68413) | 6 | mdd: look up a changelog user of either record type | jenkins+1, maloo−1 |
| LU-20648 | [68414](https://review.whamcloud.com/c/fs/lustre-release/+/68414) | 6 | mdc: fix changelog mask composition | jenkins+1, maloo−1 |
| LU-20649 | [68415](https://review.whamcloud.com/c/fs/lustre-release/+/68415) | 9 | llapi: a changelog as an Object Stream | jenkins+1 |
| LU-20650 | [68416](https://review.whamcloud.com/c/fs/lustre-release/+/68416) | 9 | llapi: fill a scan record for one FID | jenkins+1 |
| LU-20650 | [68417](https://review.whamcloud.com/c/fs/lustre-release/+/68417) | 9 | lfs: find --since, from the changelog | **jenkins−1** |
| LU-20650 | [68418](https://review.whamcloud.com/c/fs/lustre-release/+/68418) | 9 | lfs: find --changelog, the log as source | **jenkins−1** |
| LU-20650 | [68419](https://review.whamcloud.com/c/fs/lustre-release/+/68419) | 9 | lfs: find --since-cookie, per-MDT anchor | **jenkins−1** |
| LU-20650 | [68420](https://review.whamcloud.com/c/fs/lustre-release/+/68420) | 9 | tests: sanity cases for find's changelog flags | **jenkins−1** |

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

### Round 19, before the push (2026-09-03)

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

### `--fid2path` does not work on ZFS, and I got this wrong twice (2026-09-03)

**`conf-sanity test_167` fails on every ZFS configuration on PS10** —
`conf-sanity4@zfs` and all twenty `conf-sanity-special@zfs` variants — with
*"lfind --fid2path on a stopped lustre-ost1/ost1 failed"* (janitor job 69464).
It passes on ldiskfs.

**How I got it wrong.** On PS9 (job 69322) I read the results page, saw
`test_167` absent from the failure and skip listings, and concluded it had
passed on ZFS. It had not run: the highest `conf-sanity4@zfs` subtest
referenced there is 166 and the `special@zfs` sessions were skipped. Absence
meant *not run*, not *passed*. PS10 touched `conf-sanity.sh` by adding
`test_168`, the Janitor re-selected the touched subtests, and 167 reached ZFS
for the first time.

**What that bad inference was used for**, all of which now needs revisiting:

1. **AI comment `db3e58ad` was declined on it** — the reviewer asked us to
   refuse `--fid2path` on ZFS, and I replied that the premise was gone. A
   correction is posted on the thread. **The reviewer was right.**
2. **The `scan_device_run()` comment was rewritten** in round 20 to drop the
   libzpool deadlock claim, on the same evidence. The failure is a failure and
   not a hang, so the deadlock claim is still neither proved nor disproved —
   but it is no longer *disproved*, which is what I claimed.
3. **68288's commit message lost a paragraph** saying `--fid2path` cannot be
   satisfied on a ZFS target at all. That paragraph may simply have been
   right.

**Lesson for the tooling:** a `WebFetch` summary of a large results page is
weak evidence. It answers what it can see and cannot distinguish "not present
because it passed" from "not present because it never ran". Ask the Janitor's
own Gerrit comment, which names failures explicitly.

**Mechanism found, fixed, and verified (2026-09-03).** The test never passed
`--search`. An exported ZFS pool is found by reading vdev labels under a
search path that defaults to `/dev`, and the framework's ZFS vdevs are
*files in `$TMP`* (`ostvdevname 1` is `/tmp/lustre-ost1`), so
`zpool_find_config()` found nothing and `lfind` answered `cannot open
lustre-ost1/ost1: No such file or directory (2)`. The fix is one line in
test_167's existing `export_zpool` branch:
`search="--search $(dirname $(ostvdevname 1))"`, folded into LU-20637.
**PASS 167 on ZFS**; 166/167/168 all pass on ldiskfs. Full account and the
four measured-and-wrong hypotheses: `docs/rounds/round20/zfs-fid2path.md`.

That settles the three items above:

1. `db3e58ad` asked us to refuse `--fid2path` on ZFS. It works on ZFS; the
   reviewer's premise was the failing test, and the test was at fault. The
   correction already posted stands as posted — no further change.
2. The `scan_device_run()` comment claims only that a second open is *not
   free*, not that it deadlocks. A standalone program does the full double
   `kernel_init`/`spa_import`/`dmu_objset_own`/disown/`spa_export`/
   `kernel_fini` cycle twice against a real exported pool and returns. The
   comment as written is supported by measurement.
3. 68288's dropped paragraph said `--fid2path` cannot be satisfied on a ZFS
   target at all. It cannot be: it is satisfied, 20 objects named. Leaving
   it out was right, for the wrong reason.

### Settled: 68094 PS16 `lustre-initialization` is **not ours** (2026-09-03)

The user pulled the logs. `mount -t lustre` for **mds2** on
`trevis-156vm260` failed with `No such device` (19) and *"Are the lustre
modules loaded?"*, and Auster exited.

**Same session, same build, mds1 mounted and reported `Started
lustre-MDT0000`** on its own node one line earlier. Identical binaries: one
MDS node registers the `lustre` filesystem type and mounts, the other does
not. vm260's dmesg carries 34 Lustre lines — all `lctl mark` DEBUG MARKERs,
so libcfs and obdclass were live there; the last one is the mount command
itself and then nothing.

A per-node provisioning problem, not a code one. 68094 touches
`lustre/utils/`, `lustreapi.h`, a man page and a test binary — **no kernel
source at all** — and jenkins is Verified+1 on the build.

The original note, kept because the reasoning was the useful part:

### Watch, not noise: 68094 PS16 `lustre-initialization` (2026-09-03)

One enforced failure on the first sessions after round 19's push:
`review-dne-part-1`, session `4912e6ca`, *"ran 2 tests. 1 tests failed:
lustre-initialization"*. Lustre never came up.

**Not called noise yet, and not called ours.** Against it being ours: jenkins
is Verified+1 with a successful build, 68094 touches no kernel module, and the
failure came from **RHEL 10.1** while the announced enforced list has
`review-dne-part-1 on el9.7-x86_64` — a distro that was not in the plan.
Against dismissing it: it is on the change carrying the scanner API, and
`lustre-initialization` is not in the known-noise list.

**The inference to avoid:** it is the only change with an enforced failure,
which looks like the one-change cluster that means a real defect. It is not —
the CI had barely started, every change had one or two of ~30 sessions
reported and **zero** "Passed enforced" anywhere. Re-check once the sweep has
run.

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

## 68094 and adilger, as of 2026-09-05

**PS17 carries the statx record.** `struct llapi_scan_rec`'s eleven
stat-shaped fields are one embedded `lstatx_t sr_stx`, the low
`LLAPI_SCAN_*` bits are aliases of the kernel's `STATX_*` values, and the
API's own 21 bits sit above bit 31. That is on Gerrit — 68094 PS17 and
every change above it, up to 68420 PS9 — not only on `statx-port`.

Answered to adilger on 68094 PS16, in two inline replies:

| his comment | the answer given |
|---|---|
| consumer vs scanner thread counts | the same threads: `sp_thread_count` sizes one pool and the callback runs on the worker that produced the record — N scanners calling the consumer directly, not N producers feeding one |
| bulk records instead of a callback per object | measured: ~13 ns to copy one 512-byte record into a caller's array against ~1 ns for the callback, before the layout, linkea and name it points at; and the per-object handoff is libext2fs's shape (`ext2fs_get_next_inode_full()` returns one inode, already copied out of the block buffer), not something this API adds on top of a batch |
| "unfortunate to expose a new `struct llapi_scan_rec`" — use `struct statx` or `lov_user_mds_data_v2` | statx, and the switch was already under way. **`lov_user_mds_data_v2` is not a fixed size**, which is the reason it is not the base |

His nanosecond defect (`b3ce6f88`) is closed by the same change: the
conversion that dropped `tv_nsec` on all four timestamps no longer
exists.

**Still open from his 15**, and unanswered on Gerrit:

- `sp_size`/`sr_size` versioning vs `sp_want`/`sr_valid` negotiation —
  the biggest one, and untouched by the statx work;
- FlatBuffers / Cap'n Proto, the wire-format question held 2026-08-19 and
  decided off the meeting as not ours. He expects it in *this* API, and
  it is the premise of the comment the statx switch answered;
- the `sr_`/`sp_` prefix collision and the 4 hidden padding bytes — both
  real, both cheap, both worth doing once the shape settles.

He has given **68231 a Code-Review+1**, his first vote on the series.

### Held for the next round: two lreview findings on PS17 (2026-09-05)

`lreview` on `cd2c36e8f1` — the first review PS17 has had, the Gerrit AI
having fired on ps3–ps16 and never on ps17. **2 findings, severity low**,
$8.97. Both verified, both deliberately unfixed: 68094 is the bottom of an
18-commit stack, so two sentences of qualification cost a full rebase and
repush. Bundle them with adilger's versioning answer.

| # | Finding | State |
|---|---|---|
| 1 | The header says a scan wanting nothing outside `LLAPI_SCAN_DIRENT_MASK` does no ioctl per object, and that `sp_filter` runs before any I/O. Neither holds where `readdir` leaves `d_type` unset: `llapi_semantic_traverse()` (`liblustreapi_pfind.c:5960`) calls `get_lmd_info_fd()` in its readdir loop, ahead of `cb_init`. ext4 without `filetype`, XFS `ftype=0`, and the non-Lustre trees. | **Verified in the tree.** A doc claim to qualify, not a code bug |
| 2 | Four implicit padding bytes before `sr_lmm` (three consecutive `__u32`); an explicit `sr_padding` would make the hole visible and reusable | Real — and it is adilger's `2294e6ed` restated, already held above until the struct settles |

The record is **352 bytes at 68094 and 512 at the tip**: it grows as later
commits append fields, so a size quoted without its commit means nothing.

### The batch API, built 2026-09-05 (unpushed)

`llapi_scan_namespace_open()` / `llapi_scan_next()` / `llapi_scan_close()`,
commit `047658ab63` on `statx-port-fixed`, answering adilger's bulk-records
comment. A layer over the callback API: the scan runs on its own thread and
its callback copies each record, with everything it points at, into the batch
being filled.

Measured on the lab against a real mount: **+0.4% at four threads, +0.5% at
one** with the 1024 default, against **+17.6%** for a batch of 1. Off Lustre,
where per-object work is a cached `lstat()`, +5–8% — the upper bound.

lreview found three, all real, all fixed: a single-consumer contract that was
neither documented nor enforced (**a heap overflow reproduced under ASan on
the unfixed build, 5 runs of 5**), an arena that kept only its largest chunk
(worth +1.4% → +0.4%), and `(const void **)` casts punning typed pointers
under `-O2` with no `-fno-strict-aliasing`.

Verified: 16/16 unit tests on a real mount, the equality stress IDENTICAL in
all ten arms on 20,021 objects and again on a tree carrying 1000 layouts and
an LMV, sanity 56El/157c/160aa-ad 6 PASS 0 FAIL. Numbers in
`bench-data/2026-09-05/`.

**Open**: whether it goes as a change of its own on top of 68420 or is
squashed into 68094 — asked of adilger in the drafted reply, which is not
posted.

### CI on the 2026-09-04 push

`68417`, `68418`, `68419`, `68420` are **jenkins Verified−1** on PS9
(build 131103 FAILURE) — not yet diagnosed. Janitor timeouts on
`sanity1@ldiskfs+DNE` (68094) and `sanity2@ldiskfs+DNE`, plus
`sanity3@zfs` 398g on 68417; 398g is not ours, see the not-ours list.


## Rounds 20 and 21 — pushed 2026-09-04 (18 changes, 18 new patchsets)

Recorded below as it stood at 2026-09-04 00:00, before the push. 18 changes on `r16-work`,
18 Change-Ids, builds under `-Werror`, lab green.

### The 56El regression is fixed — it blocked the whole stack

`sanity 56El` failed on 68095 and every change above it, both backends,
from round 19's CI onward. **Root cause found by lreview on 68095**:
`-printf` sets `gather_all`, which sends every object through the
project-id fetch, and 68095 made the walk descend off Lustre — where
both arms of `get_projid()` answer `ENOTTY`:

| object | fetch | fails |
|---|---|---|
| symlink, device node | `LL_IOC_PROJECT` on the parent | **any kernel** — it is Lustre's own ioctl |
| regular file, dir | `FS_IOC_FSGETXATTR` | client **older than Linux 6.0** |

CI is rocky8.10 at 4.18; the lab is rhel9.7 at 5.14, which is why it
passed here all night. Fixed in 68095, carried through 68157 and 68159.
Proved by swapping `liblustreapi.so`: **unfixed exit 25 / 347 bytes of
stderr, fixed exit 0 / none**, and the test fails against the unfixed
library.

### adilger is reviewing the series

| change | verdict |
|---|---|
| **68094** | **15 comments** — four would restructure the API, see below |
| **68095** | **approved**: "very reasonable, and correctly extracts the code from `lfs find` instead of duplicating it" — plus 2 minor, both fixed |
| 68231, 68616, 68617 | 1 each, not yet triaged |

He says he is "just going through the series" and may not hold the same
view by the end, so more are coming.

**Four of 68094's comments are open decisions for the user**, and three
are alternative answers to one question:

1. `sp_size`/`sr_size` as a version number should be `sp_want`/`sr_valid`
   negotiation, `OBD_CONNECT_*` style — a newer caller against an older
   library is refused today even asking only for old fields;
2. an array-filling call beside the per-object callback, so a 1MiB
   inode-table read is not a million callbacks;
3. piggy-back on `struct statx` rather than a similar bespoke record;
4. FlatBuffers or Cap'n Proto — the wire-format question held 2026-08-19.

One is marked a defect and is timely: the record carries **second**
resolution while LU-1158 converts the tree to nanoseconds, and its
helpers have landed. It is answered for free by 3.

Two are mechanical, real and premature: `sr_`/`sp_` collide (four
headers, and `md_op_spec`), and seven consecutive `__u32`s put **4 hidden
padding bytes** before `sr_lmm`. Both are worth doing once the struct
settles.

### lreview, run locally before pushing

Serial, one at a time. Six done, six to go.

| change | findings | outcome | cost |
|---|---|---|---|
| 68094 | 4 | 3 real — **caught a fix of mine that fixed nothing**, reverted | $8.42 |
| 68095 | 2 | **found the 56El root cause** | — |
| 68415 | 4 | 3 fixed, 1 held (API shape) | $9.13 |
| 68416 | 4 | 4 fixed | $4.32 |
| 68417 | 3 | 3 fixed — severity medium | $11.68 |
| 68420 | 5 | 4 fixed, 1 held against adilger | $8.06 |
| 68158, 68160, 68157, 68231, 68616, 68617 | — | queued | — |

**One unresolved conflict between reviewers.** lreview on 68420 wants the
client version gates back (an old client exits from getopt and the case
*fails* rather than skips); adilger had just removed them (the script
matches the client it runs on). Kept adilger's answer. `CLIENT_VERSION`
is read off the client host, not the script, and `sanity.sh` uses it 30
times — so the mismatch lreview describes is expressible. **A question
for the user to put to him.**

### Also fixed this round

- **68415**: a symlink came back from the changelog scanner with no size
  and no valid bit, where both sibling scanners answer for one.
- **68416**: `llapi_scan_fid()` cannot check `@mnt_fd` belongs to the
  same filesystem as `@fid` — the wrong mount gathers a complete record
  for an unrelated object at rc 0. Documented, as its sibling already is.
  And ~70KB of calloc per object moved behind the demand mask.
- **68417**: one unreadable object ended the whole search; encrypted
  files lost every alternate name (`<mnt>//a/f` failed the subtree test).
- **68414**: all three threads were already fixed.
- **All 89 open AI threads** are triaged and closed.

### Still open

- adilger's four API questions, and his nanosecond defect.
- The `--since` duplicate-lines trade-off (a seen-FID set costs memory
  proportional to the answer).
- **Two patches have no test driving them**: `llapi_scan_changelog_test`
  is built but nothing runs it, and nothing exercises `llapi_scan_fid()`
  at all — where their three siblings each landed a suite case with the
  scanner. Owed a test patch of its own.

## Not ours: other people's tickets that show up in our CI

| Ticket | What it is | Where we see it |
|---|---|---|
| **LU-20598** | A **session timeout**, not an assertion — the ticket's summary is *"sanity-sec test_27e: Timeout occurred after 258 minutes, last suite running was sanity-sec"*, open. Ours read 241–243 min; `sanity-sec` is only the suite the clock ran out in | Every change, deterministically. The only thing producing `maloo −1` on the series. 26 of 37 other owners' changes hit it too. Gerrit words it *"1 tests failed: sanity-sec"*, indistinguishable from a real failure — check Maloo for the timeout line |
| **LU-20523** | MDS LBUG in `tgt_grant_sanity_check()` when the ZFS MDT quota is lowered below the outstanding client grant — `sanity` **805** and **807a**. Open, filed 2026-07-25 by Oleg Drokin, affects 2.17.0 / 2.15.8 | The `%% CRASHED %%` sessions in `review-dne-zfs-part-1`. Read off 68418's crash dump 2026-09-02 |
| **LU-17857** | `sanityn test_cleanup: Autotest time out` | `review-dne-*-part-5`, six of our changes so far |
| **LU-19027** | `sanity` 271d/271f `-1 resend occured` | Data-on-MDT read-on-open |

**`sanityn` test_51d**, seen on 68340 PS3 as a `sanity-dom` failure
(`review-dne-part-4`, session `9df28be8`, 2026-08-29). `sanity-dom` runs
`sanityn` as a sub-suite, so Gerrit's `sanity-dom,sanity-quota` misnames it —
nothing in `sanity-dom`'s own subtests failed. *"rss before: 824, after 860,
some pages remained"*, an mmap/layout-lock test asserting `Rss` is exactly
zero after revocation. **Categorically not ours**: 68340 is 18 lines in
`lustre/utils/liblustreapi_pfind.c` and 51d is `dd` + `multiop` + `smaps`,
with no path between them. LU-10584 is the identical signature but
Resolved/Fixed in 2.10.6 (2018), so there is nothing open to annotate
against.

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
