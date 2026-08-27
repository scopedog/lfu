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
