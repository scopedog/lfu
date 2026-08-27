# Queued for the next patchset (round 11)

Findings since the 2026-08-26 push that are **not** in what is on Gerrit.
Do not push for these alone — batch them with whatever this round's CI
returns. One patchset per review cycle.

`round11-code.patch` applies to `lu-20650-since` (`e0265228c5`, the
`--changelog` commit), and is also parked as `stash@{0}` in
`~/projects/lustre/lustre-scanfid`.

| Change | Finding | Verdict |
|---|---|---|
| 68418 | `liblustreapi_pfind.c:3558` is 82 columns — a tab counts as 8 | **real**, fixed in the patch |
| 68417 | `'time_t' may be misspelled - perhaps 'timeout_t'?` | **noise** — `time_t` already appears 6 times in that header (`fp_atime`, `fp_mtime`, `fp_ctime`, `fp_newery`); it is the file's own convention |
| 68288 | Maloo `review-dne-subtest-change` failed | **real, and open** — see below. The earlier "superseded, no action" reading is wrong: it recurred on PS3 |
| 68420 | `sanity` 160aa/160ab/160ac are gated on `MDS1_VERSION >= 2.17.58` | **real** — the tree is 2.17.57, so all three skip everywhere. Needs a decision, see below |

## 68288: test_166 fails on the current patchset

`review-dne-subtest-change` failed conf-sanity on **PS1 (08-25 01:31), PS2
(08-26 16:35) and PS3 (08-27 10:19)**. PS3 is current, so this is not the
superseded-patchset case; and three identical failures is the workflow's own
threshold for deterministic rather than flaky.

The MDS≠client fix from the two-node lab landed in **PS2**, and PS3's
`conf-sanity.sh` is byte-identical to PS2's — so the fix is in and the failure
survived it. Whatever this is, it is a second failure mode.

What points at our code rather than the tree:

- **0 of 170** other owners' open changes with a Maloo run since 08-22 failed
  conf-sanity in any session. Every previous triage in this series used the
  owner-ratio the other way round; here it inverts.
- `review-dne-subtest-change` runs only the subtests a patch changed, and the
  only conf-sanity subtest 68288 adds is test_166.

What argues it is narrow, not broad: the **Janitor's `conf-sanity4@ldiskfs+DNE`
passed on PS3** (job 68932, Success 13865s) with 165 and 166 absent from its
skip list — so both ran and passed there. The difference between the two is
that the Janitor runs 166 late in a full chunk, where a previous test has left
the filesystem mounted, while subtest-change runs it alone and therefore takes
the `is_mounted $MOUNT || setup_noconfig` branch. That is a hypothesis, not a
finding — the session page needs the Maloo login.

**Blocked on:** the subtest and the failure mode (timeout vs assertion) off
Maloo. Ask; do not infer.

## 68420: the changelog tests cannot run

The tree is `2.17.57_59_gd1b91aa` and the three new tests gate on `2.17.58`, so
the Janitor skips all three in **every** sanity chunk on both backends
(`160aa(Need MDS >= 2.17.58 for lfs find --since)` and the other two, job
68925). 68420's `Verified+1` says nothing about the changelog work.

The gate is not simply wrong: 160ab drives `changelog_register` and
`changelog_chmask`, which is the path **68413 (LU-20647)** and **68414
(LU-20648)** fix, and neither has landed. So the tests do want a gate — but
`2.17.58` is a version the tree will not reach for a long time, and until it
does nobody will notice these are dormant.

The series already has the alternative: 68288 PS2 removed exactly this kind of
gate from tests 165 and 166 and probed for the option instead — *"the option,
not a version: see test_165"*. That is not available here yet, because
`--since`, `--changelog` and `--since-cookie` are in `lfs_find_parse.c`'s
option table but **not in `lfs find`'s usage text** in `lfs.c`, so there is
nothing for `--help` to match. Adding them there is worth doing regardless.

**The user's call**, since it depends on when 68413/68414 land: probe the
option (and add the three to the usage text), or re-gate on the version those
two actually land in.

Also outstanding, not a code fix: Gerrit warns *"subject >50 characters"* on
most of the series. It is a warning and the commit-msg hook's own limit is 62,
but it is a house preference worth honouring when the messages are next
touched.

## 68340: the AI review, six comments, all six real

Posted 2026-08-27 03:47 on PS1, the first AI review on the series in a while.
Every one verified against the tree before being written down.

| Where | Finding | Verified by |
|---|---|---|
| `liblustreapi_pfind.c:297` | `convert_lmdbuf_v1v2()` clears `lmd_stx` but **not** `lmd_fid`, while the other hunk clears both | v1 starts with `lmd_st`, v2 with `lmd_fid` then `lmd_stx` (`lustre_user.h:1204-1216`), so those 16 bytes are v1's `st_dev`/`st_ino`. Same defect class the patch exists to fix, inside the patch |
| `liblustreapi_pfind.c:423` | the new comment says the buffer holds the name written for the ioctl; true only of the `parent_fd` branch | the `if (ret && type == GET_LMD_INFO)` block sits after **both** branches, and the `dir_fd` branch never `snprintf`s a name. The memsets are right, the comment is too narrow |
| `liblustreapi_pfind.c:430` | `lmd_lmmsize` is stale on the lstat path too | `llapi_get_lum_file_fd()` does `memcpy(lum, &lmd->lmd_lmm, lmd->lmd_lmmsize)` (`liblustreapi_layout.c:6104-6106`). `convert_lmdbuf_v1v2()` zeroes it; this path does not. Bounded by the `> lumsize` check, so not an overflow — but a stale length in a public API |
| commit message | *"report a FID made of one"* is unsupported | at `5afbab284e`, `lmd_fid` is read **only** in `lustre/llite/dir.c:2404`, nowhere in `lustre/utils`, and `fid_is_sane()` is not compiled into utils at all. The reader is `scan_rec_mdt()`, which **our series** adds — 68340 is standalone on master, so its own tree cannot show the effect. The `-btime`/`-attrs` half of the claim does hold |
| commit message | the subject overstates the change | it clears fields before reuse rather than stopping the reuse |
| commit message | wants a `Fixes:` tag | the bot proposes `11aa7f8704c4 ("LU-11367 som: integrate LSOM with lfs find")` — **verify that sha before using it**, the way round 8 did for 68231 |

Note the shape of the fourth: this is the **stack-blindness pattern inverted**.
Usually the bot misses that a later change fixes what it flags; here it is right
precisely because 68340 is *not* stacked, and our message described an effect
that only exists once the series is applied on top.
