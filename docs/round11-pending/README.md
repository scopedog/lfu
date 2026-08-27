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

What pointed at our code rather than the tree:

- `review-dne-subtest-change` runs only the subtests a patch changed, and the
  only conf-sanity subtest 68288 adds is test_166.
- **Retracted:** the *"0 of 170 other owners failed conf-sanity, so the
  owner-ratio inverts"* argument. The count was arithmetically right and
  evidentially worthless — see the note on counting below. The diagnosis below
  rests on the session log and needs none of it.

### Diagnosed from the session log — it is test_166, and the cause is DNE

The user pulled the log (`conf-sanity_2026-08-27_1241.zip`, session
`b6cb4274`). It is an assertion, not a timeout:

```
conf-sanity test_166: @@@@@@ FAIL: --fid2path lost 19 paths
  = /usr/lib64/lustre/tests/conf-sanity.sh:13076:test_166()
```

**`review-dne-subtest-change` runs a changed subtest twice**, which is what
exposed this and is the single most useful thing to know about that session:

| Iteration | `d166.conf-sanity` FID | MDT | Result |
|---|---|---|---|
| 1 | `[0x200000bd1:0x2:0x0]` | MDT0000 | **PASS** — *"--fid2path resolved 20 objects from 21 names, hardlink once"* |
| 2 (`repeat 2/ iter`) | `[0x240000bd0:0x1:0x0]` | **MDT0001** | **FAIL** — lost f1…f19, i.e. all of `$want` |

Proof, from `onyx-156vm87`'s debug log, which hosts MDT0001:

```
mdt_reint.c:537:mdt_create()) @@@ lustre-MDT0001: create
    (d166.conf-sanity->[0x240000bd0:0x1:0x0]) in parent [0x200000007:0x1:0x0]
```

The parent (the root, `[0x200000007:0x1:0x0]`) is on MDT0000 and the child was
created on MDT0001 — a remote directory. MDT0000's side of it goes through the
cross-MDT `out_handler.c` path, which is itself the tell. 1560 references to
sequence `0x240000bd0` sit in MDT0001's log: the twenty files are all there.

**The defect is ours and it is in the test.** test_166 does a plain
`mkdir -p $MOUNT/$tdir` and then scans only `$(mdsdevname 1)` — MDT0000. Under
DNE a fresh directory can be placed on any MDT, so the scan is looking at the
wrong target and correctly reports nothing. **test_165 already gets this right**
and the fix is to copy it:

```
-	mkdir -p $MOUNT/$tdir
+	mkdir_on_mdt0 $MOUNT/$tdir || error "mkdir $tdir failed"
```

(`mkdir_on_mdt0` is `$LFS mkdir -i 0 -c 1`, so it pins the directory to the
target the test scans. `$MOUNT` rather than `$DIR` still holds — that part of
the test was right.)

**This also explains every other observation, which the earlier hypothesis did
not:**

- The Janitor's `conf-sanity4@ldiskfs+DNE` passed because it runs 166 **once**,
  and that once landed on MDT0000. It is a coin toss, not a pass.
- The two-node lab passed because it has **one MDT** — there was nowhere else
  for the directory to go. A single-MDT lab structurally cannot see this, the
  same way the single-node lab could not see the MDS≠client bug.
- It survived the PS2 fix because it is unrelated to it.

**The earlier reading in this file was wrong** and is left here on purpose: it
blamed the `is_mounted $MOUNT || setup_noconfig` branch on the theory that
running alone was the variable. Running alone was not the variable; running
*twice* was. Both readings fit the Gerrit-level evidence equally well, which is
exactly why that evidence was not enough.

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
| commit message | wants a `Fixes:` tag | the bot proposes `11aa7f8704c4 ("LU-11367 som: integrate LSOM with lfs find")`, 2018-11-01 — **checked, and it is the right one**: it introduces `lov_user_mds_data_v2`, `convert_lmd_statx()` and `llapi_get_lum_file_fd()` in one commit |

Note the shape of the fourth: this is the **stack-blindness pattern inverted**.
Usually the bot misses that a later change fixes what it flags; here it is right
precisely because 68340 is *not* stacked, and our message described an effect
that only exists once the series is applied on top.

## 68094: closed. A timeout, and a lesson about counting

68094's `review-dne-zfs-part-3` conf-sanity failure on PS10 is, from the
session, *"Timeout occurred after 201 minutes, last suite running was
conf-sanity"*. No subtest failed. **Not ours, twice over:** a wall-clock
timeout is not an assertion, and 68094's tree (68231 + 68094) contains no
`conf-sanity.sh` change at all — there is no conf-sanity subtest of ours in
that build to fail. 201 minutes is also the familiar shape here; LU-20598's own
title is *"Timeout occurred after 258 minutes"*.

**The counting lesson, which is the part worth keeping.** Maloo's Gerrit
comment renders a session timeout and a real assertion failure **identically**,
as `1 tests failed: <suite>`. Measured: across our 18 changes and 170 of other
owners', **0 of 283** such messages contain the word "timeout". The failure
mode exists only on the session page, behind the login.

So any tally built from `gerrit query --comments` — including every
owner-ratio in [[lfu-autotest-known-noise]] — silently mixes environment with
defect. That does not invalidate the ratios used *comparatively* (both sides of
the ratio are mixed the same way), but it does invalidate reading a low
absolute count as *"nobody else has this defect"*. That is precisely the
mistake made against 68288 this morning: "0 of 170 owners failed conf-sanity"
was reported as a strong signal when a good share of any such column is
timeouts, and a suite that merely happened to be running when the clock ran out
is not a failing suite.

**The rule that follows:** the owner-ratio can say *"this looks tree-wide"*. It
can never say *"this is ours"* — for that, get the log.
