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

---

# Round 11 is built and verified — NOT pushed

Applied 2026-08-27. Safety branches `backup-pre-round11-20260827`
(`lu-20650-since`) and `backup-pre-round11-lmd-20260827`
(`stale-lmd-buffer`) in `~/projects/lustre/lustre-scanfid`.

**What went in — three code changes and five subjects.**

| Change | What |
|---|---|
| 68288 | `mkdir -p` → `mkdir_on_mdt0` in test_166, the DNE placement bug |
| 68418 | the 82-column line wrapped |
| 68340 | `lmd_fid` cleared in `convert_lmdbuf_v1v2()`; `lmd_lmmsize`/`lmd_padding` cleared on the lstat path; the over-narrow comment rewritten; message re-scoped, subject fixed, `Fixes:` added |
| 68415, 68417, 68418, 68419, 68420 | subjects cut to ≤50 |

**Verification.**

- **Code delta is exactly the two intended stack fixes** — `git diff` against
  the backup branch shows the test_166 mkdir and the line wrap, nothing else.
- **Checkpatch, per patch, before and after:** identical everywhere except
  68418, whose warning count goes **1 → 0**. Zero errors on all 16 + 68340.
- **Builds:** `liblustreapi.la lfs lfind` at stack HEAD, on 68340's branch,
  and per-commit on 68418/68419/68420 — all rc=0 with **zero diagnostics**
  under `-Wall -Werror`.
- `bash -n lustre/tests/conf-sanity.sh` clean.
- **All 16 subjects ≤50**, 16 unique Change-Ids, base still `5afbab284e`, no
  message body line over 70.

**What a push would cost:** 9 changes are byte-identical to their current
Gerrit revision and keep their patchset and votes — 68094, 68095, 68156, 68157,
68158, 68159, 68160, 68163, 68231. **8 take a new patchset**: 68288 PS3→PS4,
68340 PS1→PS2, and 68415–68420 PS1→PS2.

**Still not done, and deliberately:**

- **68420's version gate** — unchanged, still `MDS1_VERSION >= 2.17.58`, still
  skipping everywhere. The user's call; see above.
- **68231's stale Verified-1** — needs a `BUILD` comment or nothing. The
  user's call.
- ~~No lab run.~~ **DONE 2026-08-27 — the fix is verified on a 4-MDT lab.**
  `tests/lab-dne166/`, results in
  [`bench-data/2026-08-27/dne166-lab.txt`](../../bench-data/2026-08-27/dne166-lab.txt).
  Pre-fix: **PASS then FAIL, with autotest's message verbatim** (*"--fid2path
  lost 19 paths"*). Post-fix: **4/4 PASS**. 165 and 166 also pass in sequence.
  The mechanism was measured, not assumed: a stock DNE filesystem ships a ROOT
  default LMV so plain mkdirs under the root round-robin MDT0,1,2,3, and
  `lfs mkdir -i 0` overrides it.

## 68420's gate: HELD, by the user's decision (2026-08-27)

**Decision: leave `MDS1_VERSION >= 2.17.58` alone and revisit once the `lfs
find` options and the changelog fixes have landed.** So the three tests
skipping everywhere is now a deliberate state, not an open defect — do not
re-flag it as one.

**The trigger for revisiting:** 68413 (LU-20647), 68414 (LU-20648) and the
`--since`/`--changelog`/`--since-cookie` options landing. At that point the
gate must be re-checked against the version they *actually* land in — 2.17.58
was chosen before any of them had a landing version, and there is no reason to
expect it to be the right number.

**Two things to carry with the hold, because a dormant test is easy to lose:**

- **`Test-Parameters: testlist=sanity env=ONLY=160aa,160ab,160ac` is now a
  guaranteed-wasted session.** It buys a targeted run, on every patchset, of
  exactly the three tests that cannot execute — the run can only ever report
  three skips. Worth dropping until the gate comes down, and restoring with it.
  Left in place for now: it is the same 68420-testing decision the user has
  just taken, not a separate one.
- **Nothing in the commit message says the gate exists**, so a reviewer reading
  68420 sees three tests and no hint that none of them can run. One sentence
  would preempt the question. Not added — the user said hold, and this is their
  change to describe.

---

# AFTER PUSHING ROUND 11 — do these, in this order

Written down because the push is the noisy part, and these are what gets
forgotten once it succeeds.

## 1. Tell Artem the series has moved (PR 186)

**Promised to him in writing** — *"I will comment here when it is up"* — and he
is holding off on purpose, because everything downloadable still has `sr_gen`
mid-struct. Until this comment goes out, he is blocked on us.

Post to <https://github.com/TheLustreCollective/lustre/pull/186>, filling in the
new patchset number:

> The next patchset is up. It carries both fixes from this review: `sr_gen`
> moved to the end of `struct llapi_scan_rec`, so your FFI mirror is correct
> exactly as written; and `llapi_scan_device.3` corrected, since a strict SOM
> sets `LLAPI_SCAN_SIZE` and not `LLAPI_SCAN_LAZY_SIZE` — the code fix for that
> one is still yours to make.
>
> ```sh
> git fetch https://review.whamcloud.com/fs/lustre-release refs/changes/20/68420/<N>
> git checkout -b lfu FETCH_HEAD
> ```
>
> That is the whole 16-commit series down to base `5afbab284e`; the tip carries
> every ancestor. To find `<N>` without the browser:
>
> ```sh
> git ls-remote https://review.whamcloud.com/fs/lustre-release 'refs/changes/20/68420/*'
> ```
>
> — highest numeric ref wins; ignore `.../meta`.

**Verify the ref resolves before posting it.** `git ls-remote` the pattern and
check that the number you are about to quote actually exists: a wrong patchset
number sends him to a tree that is not the one described.

## 2. Answer and resolve the Gerrit threads this round addressed

Routine step 6. Round 11 answers 68340's six AI comments — reply against **the
revision each comment was left on**, not the current one, and read a thread's
resolved state off the **last reply's** `unresolved`, never the root's.

## 3. Consider setting a Gerrit topic on the series

It has none (`topic=(none)` on 68094, 68420, 68340). A topic groups the changes
in the web UI and lets anyone fetch or review the series as a unit instead of
being told which change is the tip — which is exactly the question Artem had to
ask. **A topic can be set without a new patchset**, so it costs nothing.

## 68414's AI review (2026-08-27 17:25) — 3 comments, all 3 verified real

Arrived 13 minutes after 68414's Maloo verdict, consistent with the 16–27 min
trigger. **Not yet fixed** — this is kernel code in `mdc`, and 68414's original
fix was lab-verified before its push, so these want the same treatment.

| Where | Finding | Verified |
|---|---|---|
| `mdc_changelog.c:821` | **A real gap in 68414's own fix.** Two *non-zero but disjoint* masks intersect to zero, and the record test reads zero as "no filter" — so `in & out == 0` returns **every** record type instead of none | Confirmed at base: `chlg_ioctl()` composes `in.cf_mask & out.cf_mask` (:811-814) and the record test is `if (crs->crs_user_mask && !(crs->crs_user_mask & BIT(...)))` (:222). 68414 adds the `out == 0` arm but leaves the disjoint case |
| `/COMMIT_MSG` | wants `Fixes: 41b55cf2309d ("LU-19296 changelog: Add user-specific changelog filtering")` | **Checked** — the sha exists, dated 2026-03-15, and carries 9 references to `cf_mask`/`crs_user_mask`. It is the right commit |
| `sanity.sh:22542` | `changelog_chmask()` sets the mask on **all** MDS nodes but only `$SINGLEMDS` is restored, so with `MDSCOUNT > 1` the others are left at ALL | Confirmed — `changelog_chmask()` is `do_nodes $(mdts_nodes) $LCTL set_param mdd.*.changelog_mask` (`test-framework.sh:11403-11407`) |

**The first one is the interesting one and it is the same bug one case further
along.** 68414 fixes "the registered user has no mask"; the bot found "the two
masks do not overlap". Both end at `crs_user_mask == 0`, and both are then read
as unrestricted. The honest fix distinguishes *no filter* from *empty filter*
rather than adding a third arm — otherwise the next disjoint case finds the
same hole.

**Decision needed:** fold into round 11 (which delays the push and needs
another lab, since this is kernel code) or take it as round 12. 68414 is
currently one of the **nine** changes round 11 does **not** move, so fixing it
makes it a tenth.

### FIXED, and folded into round 11 (the user's call)

All three addressed on branch `lu-20648-changelog-user-mask`; safety branch
`backup-pre-r11-68414-20260827`. **68414 becomes the tenth change round 11
moves**, PS1 → PS2.

**The encoding, not a third arm.** Adding `else if (in & out == 0)` would have
fixed this one case and left the next. `crs_user_mask` now *names the record
types to deliver*:

- `chlg_open()` initialises it to `~0ULL` — everything, i.e. unfiltered;
- the record test loses its zero special case and is a plain
  `if (!(crs->crs_user_mask & BIT(rec->cr.cr_type)))`;
- an empty intersection is no bits, which now means **no records** rather than
  every record.

Behaviour is unchanged for every case that was already right: both masks zero
still delivers everything, one zero still passes the other through.

**Two things checked because the diff changed when `BIT()` is evaluated.** The
old test short-circuited on `crs_user_mask == 0` and never touched
`BIT(cr_type)`; the new one always does.

- `cr_type` tops out at `CL_DN_OPEN = 24` (`CL_LAST` = 25), far below 64, so
  `BIT()` cannot be undefined.
- `crs` has exactly one allocation site, `OBD_ALLOC_PTR(crs)` in `chlg_open()`
  at :638, with the init at :652 — before `file->private_data` is set, so no
  reader can observe a zeroed mask.

**`test_160za` was written, then REMOVED — and that is the important part.**
It asserted the disjoint case returns no records. It passed. Then the control
(the pre-fix module, rebuilt from the top and confirmed by an `md5sum` guard on
the installed `mdc.ko`) **passed too**. A test that passes against the broken
code is a test of nothing, so it is gone.

Chasing why produced the real finding: **the bot's severity does not
reproduce.** On the *pre-fix* module, `lfs changelog --user U --mask mkdir` for
a user registered `--mask creat` returns **nothing**, not the whole log. The
server already restricts delivery to the user's own mask — a user with
`mask=MARK,CREAT` is only ever sent CREAT records — and the requested mask is
applied there too, so the client-side `crs_user_mask == 0` never has anything
to fail to filter.

So the code change stands as **hardening, not a user-visible fix**: the
client-side test should mean what it says, and `llapi_changelog_start_user()`
takes a raw mask from an application. The commit message says exactly that
rather than claiming a wrong answer nobody can observe.

**Also:** `Fixes: 41b55cf2309d` added (verified — that commit introduces the
composition and the record test), the subject cut from 61 to 44 characters, and
`test_160z` now widens only `$SINGLEMDS`, matching the facet its `stack_trap`
restores.

**Being built and run on `lfu-mask-lab`** — this is `mdc` kernel code that
cannot be compiled locally (the working tree is `--disable-modules
--disable-server` on a 7.0 kernel), and 68414's original fix was lab-verified
before its push.

## 68094's AI review (2026-08-27 18:30) — 5 comments, all 5 real

23 minutes after 68094's Maloo verdict; the trigger is now 8 for 8. **68094 is
currently one of the four changes round 11 does NOT move**, so acting on these
makes it a sixteenth.

| Where | Finding | Verified |
|---|---|---|
| `liblustreapi_scan.c:549` | **`sp_size` need not land on a field boundary.** Accepted range is `[MIN_SIZE, sizeof]`; `memcpy(&spl, sp, sp_size)` with 25–31 copies **half of `sp_filter`**, and `st.ss_filter` is then called through it | Measured: `sizeof(struct llapi_scan_param)` = 56, `sp_filter` at **[24, 32)**, `LLAPI_SCAN_PARAM_MIN_SIZE` = 24. So 25–31 is accepted and yields a partial function pointer |
| `lustreapi.h:621` | **`sr_attr_flags` is unmasked `stx_attributes`**, so it carries raw inode flags, not only `STATX_ATTR_*` as the header says | `ll_dir_ioctl()` does `stx.stx_attributes \|= body->mbo_flags` (`llite/dir.c:2485`). Our namespace path assigns it raw (`liblustreapi_scan.c:192`) while **the device path masks** (`libscan_ldiskfs.c`, "only these i_flags bits share their values"). `lfs find` masks too (`liblustreapi_pfind.c:1558`). **Our two scanners disagree about one documented field** |
| `lustreapi.h:631` | **A foreign LMV breaks "always in the lmv_user_md form."** A namespace scan delivers the raw `lmv_foreign_md` blob | `llapi_scan_lmv_size()` **already branches on `lmv_is_foreign()`** (`liblustreapi_scan.c:100-107`), and `cb_find_init()` guards **5** reads with it. The code knows; the contract does not |
| `llapi_scan_namespace.3:70` | the page documents some record fields and none of the `LLAPI_SCAN_*` constants — `sr_fid` especially, which most consumers reach for first | fair on inspection |
| `lustreapi_internal.h:311` | *"Both are enumerated"* but only one macro is defined | fair — leftover from a two-macro version |

**Two of these are API-contract decisions, not defects with an obvious fix**,
and the bot phrased both as questions:

- **`sr_attr_flags`** — mask it in the namespace path to match the device path
  and the header, or add an `sr_attr_mask` beside it and let the consumer do
  what `lfs find` does? Masking is smaller and makes the two scanners agree;
  carrying the mask preserves information a consumer might want.
- **`sr_lmv`** — say in the contract that a consumer must check `lum_magic`
  first, or give a foreign LMV its own `sr_valid` bit? A bit is friendlier and
  costs one constant; the contract change is free but pushes the check onto
  every consumer, and PR 186 has already shown how that goes.

**`sp_size` has an obvious safe fix** and no contract question: reject a size
that does not end on a field boundary. Today the only real values are
`LLAPI_SCAN_PARAM_MIN_SIZE` and `sizeof(*sp)`.

## 68413's AI review (2026-08-27 18:32) — 3 comments, and one overturns our own decision

11 minutes after its verdict, so the trigger window is wider than the 16–27 min
this file has been quoting.

**1. The version gate — and the evidence changes the 68420 decision.** The bot
says *"No other gate in lustre/tests is above the current tag; should this be
2.17.57?"* Checked, and it is right, more strongly than it put it:

```
tree tag: 2.17.57_59_gd1b91aa

every version_code gate at 2.17.56+ anywhere in lustre/tests:
  2.17.56   <- replay-single, sanity-quota, sanity-sec  (BELOW the tag: passes)
  2.17.58   <- sanity.sh:22536, 22583, 22626  — ALL THREE ARE OURS (160aa/ab/ac)
```

Add 68413's `test_160y` and 68414's `test_160z`, and **every gate above the
current tag in the entire test suite belongs to this series.** Nothing else
does it.

**So the house convention is the opposite of what I assumed on 08-27 morning.**
I framed 2.17.58 as a legitimate interop gate and recommended holding it. The
tree says a gate is set at a version the branch has **reached**, so the test
runs immediately on the change that adds it — interop still skips, because an
older MDS or client reports a lower version. Gating *above* the tag means the
test runs nowhere until a tag is cut, which is what we have: 160aa/ab/ac,
160y and 160z have never executed anywhere, including on the targeted
`Test-Parameters` sessions those changes pay for.

**This is worth putting back to the user**, because the 08-27 hold was decided
on my framing. `2.17.57` makes all five tests run now and keeps interop
skipping.

**2. 68413 and 68414 are coupled, and 68413 alone is a regression.** Enabling
lookup for a plain `CHANGELOG_USER_REC` user makes `cf_mask = 0` the normal
case, and pre-68414 `chlg_ioctl()` composes `in & 0 = 0`, which the record test
reads as unfiltered. So `lfs changelog --user cl1 --mask creat` on a plain user
**succeeds and prints every record type** where it used to stop at `-ENOENT`.
68414 is exactly the fix. They should land together, and 68413's message should
say so rather than leaving a window where the tree is worse than before.

**3. `Fixes: 5b85a4eb7510 ("LU-19296 changelog: retrive changelog user info
from MDT")`** — verified: the commit exists (2025-10-10), mentions
`mdd_changelog_user_lookup_cb` twice, and is in 2.17.0, so b2_17 wants the fix.

### DONE — all five gates changed to 2.17.57 (the user reversed the hold)

| Change | Test | Gate |
|---|---|---|
| 68420 | 160aa, 160ab, 160ac | `MDS1_VERSION >= 2.17.57` |
| 68413 | 160y | `MDS1_VERSION >= 2.17.57` |
| 68414 | 160z | `CLIENT_VERSION >= 2.17.57` |

**The skip messages were changed too** — they all named 2.17.58, and a skip
that misreports the version it wants is worse than the gate itself, because it
is the only thing a reader sees in the results.

Verified: **no `2.17.58` remains** in any of the three worktrees, and the only
other gate at 2.17.56+ anywhere is the pre-existing 2.17.56, which passes.
`bash -n` clean on all three.

Also folded into 68413 while its message was open: the verified
`Fixes: 5b85a4eb7510` and a paragraph saying it wants LU-20648 beside it,
because landing it alone trades a lookup failure for a wrong answer.

**Round 11 now stands at 17 changes moving**, 68094 being the only one of the
19 still untouched — its five AI comments are triaged but not applied, two of
them being contract decisions still with the user.

Whole-round verification after the gate change: 16 commits / 16 Change-Ids /
base `5afbab284e`; checkpatch **0 errors** across all 19 patches (21 warnings
and 187 checks, all the known moved-code noise); `liblustreapi.la lfs lfind`
builds rc=0 with **zero** diagnostics under `-Wall -Werror`.

### 68094 — all five applied (the user's decisions)

**`sr_attr_flags` masked** with `stx_attributes_mask`, so the field carries only
what the server declared and means what the header says. **Foreign LMV got its
own bit**, `LLAPI_SCAN_LMV_FOREIGN = 0x20000000`, chosen above the block the
rest of the series fills.

**The review only saw half of the foreign case.** It flagged the namespace path;
checking the other one showed `scan_lmv_to_user()` in the **device** path also
handles `LMV_MAGIC_FOREIGN`, copying the blob out as `lmv_foreign_md` with a
byte-swapped header. Both paths now set the bit. A review that names one call
site is not a survey of them.

**Both doc items done:** `llapi_scan_namespace.3` gains a *"The record's fields
and their bits"* section covering every field and constant, including
`sr_parent_fd`/`sr_fd` lifetime and that `sr_attr_flags` is masked; and the
`lustreapi_internal.h` comment no longer promises two enumerations while
defining one — it describes `LLAPI_SCAN_MDT_MASK` and points at the public
`LLAPI_SCAN_DIRENT_MASK` for the dirent half.

**A mistake of mine, caught by building.** Resolving the 68156 rebase conflict
split a comment block, orphaning its body after a `#define` — a syntax error
(`missing terminating ' character` on `target's`). **The rebase completed
happily, because git does not compile.** Repaired, and every commit is now
built individually rather than only at HEAD, since that breakage was mid-stack
and invisible from the tip.

Verified after all of it: 16 commits, 16 Change-Ids, base `5afbab284e`,
**every commit builds alone** with zero `-Wall -Werror` diagnostics, checkpatch
**0 errors**, `groff -man` clean on both man pages.

**Round 11 now moves 18 of 19.** Only 68231 is untouched.

## 68156 + 68158 AI reviews (2026-08-27 20:03/20:07) — 5 comments

The reviews did arrive, 16 and 28 min after their verdicts, so the earlier
worry that the bot had gone selective was premature. **68157 still has none at
45+ min**, so it may yet be skipped.

### The one that matters: `LMV_USER_MAGIC` on a real directory stripe (68156)

**Confirmed on every claim, and it is our defect.**

| Fact | Evidence |
|---|---|
| the device path stamps `LMV_USER_MAGIC` | `liblustreapi_scan_device.c:244` |
| a namespace scan carries `LMV_MAGIC_V1` | `llite/dir.c:2274` sets it for `LL_IOC_LMV_GETSTRIPE` |
| `LMV_USER_MAGIC` **means "default layout"** | `LMV_USER_MAGIC 0x0CD30CD0 /* default lmv magic */`; `LMV_MAGIC_V1 0x0CD20CD0 /* normal stripe lmv magic */` |
| liblustreapi dispatches on exactly that | `liblustreapi.c:2150` prints `"(Default)"`; `:2307` **suppresses the object list** when the magic is `LMV_USER_MAGIC` |
| `cb_get_dirstripe()` picks on the same basis | `liblustreapi_pfind.c:148` default → `LMV_USER_MAGIC`, `:150` otherwise → `LMV_MAGIC_V1` |

So **one striped directory reads back differently from the two scanners**, and
`lmv_dump_user_lmm()` renders a real striped directory scanned off a device as
a *default layout with its stripe list suppressed*. That is precisely the
guarantee `scan_lmv_to_user()`'s own comment and the `sr_lmv` comment make.

**And the obvious fix is unsafe.** The device path sizes the buffer with
`lmv_user_md_size(0, ...)` — header only — while setting `lum_stripe_count` to
the **real** count. Today the `LMV_USER_MAGIC` stamp is the only thing stopping
`lmv_dump_user_lmm()` from walking `lum_objects[]`. Change the magic alone and
that walk runs over `count` entries in a header-sized buffer.

**Recommendation: do NOT fix this in round 11.**

- The defect is already on the current Gerrit patchset, so leaving it changes
  nothing for the worse.
- The naive fix trades a wrong answer for a buffer over-read.
- The real fix is a design choice — carry `lum_stripe_count` as 0, carry zeroed
  entries, keep the summary form and document it, or mark the missing shard
  list with a bit the way the foreign case now is — and it interacts with the
  decision just made about `LLAPI_SCAN_LMV_FOREIGN`.
- A device-scan LMV change wants a lab, and there is no time before 23:00.

**A safe subset is available if wanted:** leave the magic alone and correct the
two comments that claim the two forms are identical, so the code and its
documentation stop disagreeing. That removes the false guarantee without
touching behaviour.

### The other four, all minor and all safe

| Where | Finding |
|---|---|
| 68156 `/COMMIT_MSG` | the body never mentions `struct llapi_scan_stats`/`sp_stats` or `LLAPI_SCAN_F_INTERNAL`, both public API a caller must know |
| 68156 `llapi_scan_device.3:89` | **already fixed today** — this is the strict-SOM paragraph corrected for Artem's `LAZY_SIZE` finding; the bot is reviewing PS9, which predates it |
| 68158 `lfs_find_parse.h:90` | `-1` means different things for `pathstart` and `pathend`; the latter means "runs to argc", and `lfs_find()` does that fixup while the header does not say so |
| 68158 `lfs_find_parse.h:98` | "0 on success, non-zero otherwise" is the one test that does not work — the give-up paths return 0, which is why `stopped` exists |
