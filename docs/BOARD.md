# The LFU board — one page

Every ticket and Gerrit id in play, and the ones that are *not* ours. Regenerate
the top table with `tests/gerrit-poll/gpoll.py`'s query; last refreshed
**2026-09-06**.

## Tomorrow: start here (end of 2026-09-17)

**Nothing is running.** VM shut down. Nothing pushed today; four Gerrit
replies and two Maloo retests are the only outward-facing actions.

1. **The stack:** `fix-0915` = **163d438831** in `~/lfs-carry-0915`, 26
   commits on 68231 PS8. The bottom four are as pushed (101891803c). All
   nine OSD commits have been lreviewed and fixed today, with the man4
   pages; tags `backup/fix-0917-*` mark each step.
2. **Watch:** the four pushed changes (Maloo still running their enforced
   sessions, only Jenkins +1 so far); the two retests requested this
   evening (68094 review-ldiskfs-ubuntu, 68157 review-dne-zfs-part-5);
   68414 PS8, whose testing the BUILD comment started.
3. **Waiting on others:** 68231, 68616 and 68617 to land -- that is what
   unblocks pushing the rest of the series. 64945 needs sbuisson's CR-1
   resolved, not a retest.
4. **Owed, none urgent:** replies in `docs/local/replies-series/<change>-<ps>.json`
   (post only after each change is pushed); the `{{...}}` escaping in
   LU-20611's description. **65026 and 68582 are NOT held** -- checked
   2026-09-20, each local HEAD equals the Gerrit current revision (65026 PS12
   = 0c050a1597, 68582 PS2 = 202bd01742), so there is nothing unpushed there.
5. **Undecided, the user's call:** comment on 68160 that PS20 is outdated;
   mark 68158-68818 WIP; abandon candidates outside LFU (67052, 65388,
   65120).

## 2026-09-21: the Gerrit AI round of 09-20/21 -- round 21, UNPUSHED

Eleven comments on five changes: **nine taken, one declined, one left to its
own patch**. Full triage in [`rounds/r-0921/notes.md`](rounds/r-0921/notes.md).

- **The stack:** transforms in `docs/rounds/r-0921/r0921fix.py`, driver
  `r0921drive.py`. New tip **`r0921-tip` = ea8bd797c5** in `~/lfs-carry-0915`,
  26 commits; `backup/fix-0921-pre` = c00708148b. Only 68094, 68095 and 68156
  change content; the 23 above carry it.
  - **68094:** `LLAPI_SCAN_ATTRS` now gates on `OBD_MD_FLFLAGS`, not on
    `stx_attributes_mask` -- llite fills that mask with a build-time constant,
    so the bit was set for every object. Man page follows.
  - **68095:** `! --foreign` on an unstriped directory prints on the LMV alone
    again, as upstream did; the record had put the getattr RPC in front of the
    shortcut. `-printf` still gathers.
  - **68156:** `/llapi_scan_device_test` added to `.gitignore`; a striped
    directory's `STATX_SIZE`/`STATX_BLOCKS` are withheld by the device scan,
    as `ll_dir_ioctl()` withholds them on a walk.
  - **Declined:** the conf-sanity `2.17.58` gate. `LUSTRE-VERSION-GEN` says
    2.17.58 and the base describes as `v2_17_58-39-g...`, so test_300 runs.
- **68414 — not ours, and the local amend was doubly wrong.** 3ddfe69873 is
  message-only (the `--amend` ran without `-a`; the `mdc_changelog.c` edit is
  still unstaged) *and* it is not based on PS9 (`968d6b5223` is not an
  ancestor; it sits on an 08-26 LU-20647 commit). Both found by the lustre-bd
  session and verified here. The comment hunk and the message rewording went
  over as text for it to apply to PS9. 68413 and 68414 are its changes.
- **65026 is PUSHED as PS13** (05d029f116), by the lustre-bd session with the
  user's approval, carrying the three fixes this round made: the three-case
  list in the message, `-EINTR` -> `-EPROTO` for a signal-killed helper, and
  the stale test_21c sentence in the 21d comment. Verified+1 from Maloo and
  jenkins went with the push, as expected; the parents 68582 PS2 and 64945 PS5
  were byte-identical so nothing else in that chain moved. **Not ours any
  more** -- that chain is lustre-bd's.
- **Owed, its own patch:** the `mdc_create()` reply-decode leak in
  `mdc_reint.c` (two returns before `*request = req`), pre-existing.
- **65026 and 68414 are no longer ours.** The other session (lustre-bd) took
  both back on 2026-09-21 -- LU-20050 is its chain, 68414 PS9 was its public
  promise -- and has read both local tips (lr-65026 at 05d029f116,
  lustre-lu20648 at 3ddfe69873), so the fixes go on from there. It also notes
  that 65026's `-EINTR` -> `-EPROTO` is a functional change and pushing it
  costs the Verified+1 that 65026 holds today; that is the user's call, and it
  is asking.
- **Verified:** per-commit build sweep, 26/26 clean; checkpatch on the changed
  commits, no new findings; **lab A/B green, ten checks** (63 -> 21 getattr
  RPCs for `! --foreign`, the striped directory's `4096 8` -> `0 0` from a
  device scan, everything else unchanged) --
  [`rounds/r-0921/r21arms.log`](rounds/r-0921/r21arms.log).
  **Not yet:** `lreview`, which gates the push.

## 2026-09-20: the 11 lreview findings fixed -- round 20, UNPUSHED

All eleven from the 09-18 lreview (8 on 68156 PS22, 3 on 68095 PS22) fixed as
transforms over the whole stack: `docs/rounds/r-0920/r0920fix.py`, driver
`r0920drive.py` (the r-0918 driver, r3 engine). New stack tip = tag
**`r0920-tip` = c00708148b** in `~/lfs-carry-0915`, 26 commits, Change-Ids
intact; `backup/fix-0920-pre` = 8680c5570a. **68094 is unchanged** (same-tree),
so only 68095 and 68156 and the carriers above them move.

- **68156 1 (defect): LLAPI_SCAN_CLS_ORPHAN**, the class the user chose.
  `scan_classify()` tests `LMAI_ORPHAN` **last**, after the OST and LAST_ID
  tests, so only what would have been VISIBLE changes class; the enum gains
  ORPHAN = 6 and CLS_MAX = 7 (ss_class[] is the last field of
  `struct llapi_scan_stats`, so growing it is an append, which ss_size
  already covers). `scan_sink_object()`'s `cls != dev->sd_visible` gate then
  withholds orphans unless LLAPI_SCAN_F_INTERNAL, which is the point.
  Traced on disk: mdd_mark_orphan_object() -> LUSTRE_ORPHAN_FL ->
  osd_attr_set() -> `lustre_to_lma_flags()` -> LMAI_ORPHAN in the on-disk
  LMA. The flag is only ever set, never cleared -- and LFSCK
  (lfsck_engine.c:126) skips on the same flag, so this matches the tree.
- **68156 2:** `scan_size()` reports `stx_blocks = 0` for a regular file with
  no trusted.lov, as mdt_pack_attr2body() does (mdt_handler.c:880). A
  directory or symlink keeps the inode's own blocks.
- **68156 3-8, 68095 2-3:** the comment and man-page items -- scan_osd_ldiskfs.so,
  `--attrs`, the ss_skipped paragraph (which now says PENDING's files are
  *not* skipped but classified ORPHAN), the five "which scanner fills this"
  comments adilger asked about in PS16, the four that narrated an earlier
  revision, fid_is_root()'s note, the projid comments.
- **68095 1:** `-printf %Li` on a foreign directory prints
  `fp_file_mdt_index` (OBD_NOT_FOUND prints nothing) rather than reading
  lfm_type out of `lum_stripe_offset`. That restores the pre-patch output, so
  there is **no Behaviour-changes line to add** to the message -- the delta
  the review found is gone rather than documented.

**Proof.** Lift-and-compare against the *unfixed* build: `scan_classify()` and
`scan_size()` lifted from 8680c5570a and from r0920-tip into one harness
(`docs/rounds/r-0920/classify-size-harness.c`, output `harness-out.txt`).
16 cases, all as expected: the two orphan cases flip VISIBLE -> ORPHAN, the
regular-file-no-layout case flips 8 blocks -> 0, and agent / OSD-internal /
OST / IDIF / BAD / NO_LMA / directory / symlink / striped-file are unchanged.
Per-commit build sweep over all 26 (`build-sweep-0920.sh`): build=0 hdr=0
tests=0 everywhere. checkpatch per commit: 68156 identical to PS22, 68095
**loses** one over-80 line and adds nothing.

**Not done, deliberately:** no push (the round waits on the Gerrit AI on PS22,
and pushes are the user's call); no lreview of the new commits yet -- that is
the gate before the next push; no VM lab, the harness being the proof that
discriminates here.

## 2026-09-20: CI check -- no human or AI comments

Nothing new to answer. Jenkins +1 and Janitor builds green on 68094 PS21,
68095 PS22, 68156 PS22, 68157 PS22, 68414 PS9; checkpatch style warnings only.
Test failures all triaged as known noise (sanity2/3 timeouts, sanity 160g,
sanity-lfsck, recovery-small 24b, sanity-quota, sanity 816) except two, both
looked up in Maloo and both far from our code:

| Change | Session | Subtest | Ticket |
|---|---|---|---|
| 68157 PS22 | review-dne-part-1 el10.1 | `sanity test_259` "missing truncate?" | **LU-20511** (Open), exact title |
| 68414 PS9 | review-dne-zfs-part-2 el9.8 | `sanity-pfl test_16b` setstripe failed | **LU-18276** (Open) -- the suite log says `No space left on device (28)` on a 24048-byte layout, which is that ticket's shape |

Both linked in Maloo and **single-session retests requested 09-20**:
68157 review-dne-part-1 (build #131959) against LU-20511, 68414
review-dne-zfs-part-2 (build #131952) against LU-18276.

Still red on both changes: `review-dne-zfs-part-4` / **sanity-quota test_2**
*"project create fail, but expect success"* = **LU-16301** (Open), the same
subtest on both, and `createmany` under a project quota limit -- server-side
accounting, nothing the series touches. **Left alone on the user's call**:
autotest already handles this one, so no link or retest from us.

## 2026-09-18: lreview after the push (missed before it) -- next round

User caught that lreview did not run before the 09-18 push. Run after, one
at a time, reports in `docs/local/lreview-0918/markdown/`.

- **68156 PS22 (b6c43adc81), $9.98, 8 findings, all verified real, none in
  today's new code.** To fix next round (do NOT push again today):
  1. (defect) scan_classify() ignores LMAI_ORPHAN (osd_attr_set() writes it
     to the on-disk LMA): open-unlinked files in PENDING and migrate/HSM
     volatiles are delivered as VISIBLE. **User chose (b): a new class
     LLAPI_SCAN_CLS_ORPHAN** (enum and CLS_MAX change; nothing landed).
  2. no-layout regular file: stx_blocks must be 0 as mdt_pack_attr2body()
     reports, not the MDT inode's i_blocks.
  3. comment typo scan_ldiskfs.so -> scan_osd_ldiskfs.so.
  4. llapi_scan_device.3: only zero-link orphans land in ss_skipped; the
     PENDING ones are item 1.
  5. llapi_scan_device.3: `-attrs` -> `--attrs`.
  6. lustreapi.h comments still say which scanner fills a field --
     **adilger PS16 asked for this and it was not finished**.
  7. comments narrating earlier revisions (libscan_ldiskfs.c:570,
     scan_sink_object "lost+found came out as", scan_sink_skip, backend.h
     "Carved from the padding").
  8. lustre_fid.h fid_is_root() comment: back to the short original.
- **68095 PS22 (eb773b585f), $5.33, 3 findings (low), all verified real:**
  1. `-printf %Li` on a *foreign* directory: the old code stored the MDT
     index over lfm_type (its own bug) and printed it; the new code rightly
     skips the store, so %Li now prints lfm_type. Print fp_file_mdt_index
     for a foreign LMV in the %Li arm, and say so in the message.
  2. get_projid ENOTTY comments: outer says "prints DEFAULT_PROJID", inner
     "prints none", code sets 0 (the rename is 68157). Fix the comments.
  3. comments narrating the change ("this walk now descends off Lustre",
     get_projid's "now picks a branch", cb_find_init "Reachable because").
- 68094 and 68157 not lreviewed: docs/comment-only and carry-only this round.

## 2026-09-18: AI round on the pushed four -- 8 fixed, 1 declined, PUSHED

**PUSHED 09-18** (user approved; parent still 68231 PS8 b7b1332a42, 68616/68617
untouched): 68094 PS21 558245365c, 68095 PS22 eb773b585f, 68156 PS22
b6c43adc81, 68157 PS22 8f508348f2. Three messages got plain-English lines
(56El --links; released-file size; bitmap skip count); trees identical to
the lab-tested 6a130160b1 stack, all 26. Stack tip now tag `r0918-tip` =
8680c5570a (the rest, 68158+, still local). 9 replies posted; open on the
four = the -B decline (68095:2701) plus the two older deliberate ones
(68095:2500, 68156:730).

Gerrit AI reviewed 68094 PS20, 68095 PS21, 68156 PS21 on 09-18 (68157
clean): 9 threads. Transforms `docs/rounds/r-0918/r0918fix.py` (round-3
engine), driver `r0918drive.py`; branch `fix-0918` untouched, new stack =
tag `r0918-tip` = **6a130160b1** in `~/lfs-carry-0915` (26 commits, all
Change-Ids intact; backup tag `backup/fix-0918-pre` = 163d438831).

- **68094:** man3 names `<linux/lustre/lustre_idl.h>` for lmv_foreign_md;
  example tests STATX_TYPE not STATX_MODE; lustreapi.h lifetime list adds
  lfsr_lmv (later commits already list it).
- **68095:** 56El drops `-type f` (dirs now reach the LMV fetch), expects 4;
  scan_rec_gather_lmv/_rest -> scan_rec_gather_begin/_finish (+ message).
  **Declined:** -B off Lustre as non-match -- a walk starting off Lustre
  already gets -EOPNOTSUPP (calloc'd fp_lmd, parent and stock alike); the
  parent only dodged it with the previous object's btime.
- **68156:** CLS_BAD comment = unknown LMA incompat bit only;
  scan_size() treats an HSM-released layout (all components, as
  mdt_hsm_is_released()) as size from the MDT inode, blocks 0/1, man page
  says so; ldiskfs error arm tests the inode bitmap before counting a skip.
  **Gap left for the OSD series:** the kernel ring marks LOV present without
  its bytes, so the released check cannot run there.
- **Verify:** own diff re-read (one comment style fixed); checkpatch
  errors/warnings identical on all 26.
- **Lab (clone VM, `~/lustre-0918`, prefix `~/r18-inst`, `/tmp/r18lab`):**
  - 56El: old check + 68094 lfs FAIL (so the AI's "passes on the parent"
    is wrong); new check + 68094 FAIL; new check + 68095 PASS.
  - HSM (archived with lhsmtool_posix, then released; `hsm_set --archived`
    alone fails release on data_version): namespace rel1 1048576/1 blk,
    relc (PFL) 2097152/1. Device scan A (old tip) 1048576/2048 and
    2097152/4096 (strict SOM, pre-release blocks); B 1048576/1, 2097152/1;
    A again = A. nrm1 lazy in all.
  - Bitmap: plugin opens with IGNORE_CSUM_ERRORS, so a corrupt checksum
    never reaches the arm (proven: 0 skips); inode-table block 78 put in the
    bad-blocks inode instead (inodes 169 free, 170-172 used): A seen 277
    skipped 4, B seen 276 skipped 3, A again 277/4.
- Replies drafted in `docs/rounds/r-0918/reply-*.json` (decline left
  unresolved); post only after the push.

## 2026-09-18: 68414 PS9 is now promised in public (done by session lustre-1b)

Another session acted on 68414 PS8 by mistake. Nothing built, nothing pushed.

- **Posted (one review, under the user's name):** COMMIT_MSG:64 -- the
  disjoint half of 160z ("-m creat" then "--mask=-mark,-creat") was lost in
  PS7, restore it; sanity.sh:22599 -- 160y deleted by rebase, keep it from
  68413 and add 160z after it; sanity.sh:22605 -- drop the CLIENT_VERSION
  2.17.58 gate. Those three left open. sanity.sh:22603 -- keep
  `v2_17_52-164-g41b55cf230`, RESOLVED.
- **Retests (build 131914):** review-dne-part-4 el10.1 sanity-quota test_0
  = LU-19169; review-dne-zfs-part-5 el9.7 sanityn test_102 ESTALE = LU-20501.
- **Found, not posted:** Andreas's PS7 went back to `changelog_chmask "ALL"`
  (all MDTs), so the commit message's "only on $SINGLEMDS" is now false --
  fix the sentence or return to the facet-only set_param of PS2-PS6.
- **PS9 must:** restore 160y (68413 PS9), restore the disjoint half (68414
  PS6), drop the client gate, fix the $SINGLEMDS line. Keep Andreas's
  cleanups: no changelog_deregister, no rm -rf, no Test-Parameters, his MDS
  gate. Start from Gerrit PS8, not the stale local copy.
- **Re-checked 09-18 (this session):** all of the above confirmed on Gerrit.
  The $SINGLEMDS problem is a real state leak, not only wording:
  changelog_chmask sets every MDT, changelog_register's per-MDT traps then
  save "ALL", and the hand trap restores mds1 only -- so on DNE, mds2..N
  stay at ALL after 160z. Retests running (~4-5 h left as of 09-18 morning).
  AI summary also floats a sentence in lfs-changelog.1 -- not promised.
- **PS9 PUSHED 09-18** (user approved); three threads answered "Done in PS9." and resolved, 0 unresolved. Andreas's +1 dropped with the new PS -- watch for his re-review and Maloo.
- **PS9 built:** `~/projects/lustre/lr-68414`, tag `l68414-ps9`
  (968d6b5223 on 68413 PS9 626307a688). sanity.sh = 68413 PS9's + PS6's 160z
  with Andreas's cleanups (his MDS gate, no client gate, no rm -rf, no
  deregister); widen/restore on $SINGLEMDS only; widening comment now agrees
  with the commit message (PS8's said the opposite). Message unchanged from
  PS8. checkpatch clean.
- **Lab (clone VM, build tree, FSNAME=p9, `/tmp/p9lab`):** fixed 1 MDT and
  2 MDTs: 160y+160z PASS, masks MARK before and after. Unfixed mdc: 160y
  PASS, 160z FAIL "--mask creat should hide MKDIR, got 1"; with that check
  echoed, FAIL "a disjoint --mask should select nothing, got 1" -- both
  halves discriminate. PS8's 160z on 2 MDTs leaves MDT0001 at the full mask
  (leak proven); PS9 does not.
- **Trap:** PS8's client gate SKIPPED 160z on the lab tree (2.17.57_181, no
  local numeric 2.17.58 tag); on Maloo it ran (~165 PASS in subtest-change),
  so the posted reply is right. Running sanity.sh with sudo from a build tree
  leaves root-owned lt-* files; chown before the next make.

## 2026-09-17 evening: CI check

- **Retests of 09-17 morning both PASSED:** 68582 PS2 and 64945 PS5 are
  Verified+1 (LU-20276, the osd-zfs OOM).
- **68414 PS8:** the BUILD comment worked -- Jenkins rebuilt (131914) and
  Maloo announced its sessions, so the change is being tested at last.
- **Two new failures on the pushed four, both known upstream, retested:**
  68094 PS20 review-ldiskfs-ubuntu, sanity-lnet test_236 "Expect peer NI
  state down" = **LU-19605**; 68157 PS21 review-dne-zfs-part-5, sanityn
  test_cleanup Autotest time out = **LU-17857**. Both linked in Maloo and
  single-session retests requested.

## 2026-09-17: Artem asked for the lfind -> lfs find patches

Sent him `docs/local/artem-lfs-find/`: `old-68160-ps20-lfind.patch` (what
Gerrit shows, PS20), `new-68160-lfs-find-device.patch` (local c26f54fc32,
same Change-Id, unpushed) and a README with the before/after commands and
the file list, for a slide. A range-diff between the two is useless -- the
code moved to other files, so git reads them as unrelated.

LU-20611 was already retitled and rewritten (09-16); nothing owed there but
the inconsistent {{...}} escaping in its description.

## 2026-09-17 afternoon: lreview 68816-68818, 23 findings fixed (NOT pushed)

lreview ($12.30, reports `docs/local/lreview-0917b/markdown/`): 68816 11
(high), 68817 5, 68818 12. Two agents verified all 28 against the tree.
`fix-0915` = **3a4298c58c** (before: tag `backup/fix-0917-pre-rpc` =
afd3466f45; after: `backup/fix-0917-rpc-lab`). Only the top 3 commits changed.

- **Declined (5):** imperative subjects (68816, 68817, 68818) and
  Test-Parameters (68816, 68818): house style / deliberate preview.
- **68816:** dt_index_read() takes only II_FL_NOHASH|NOKEY|VARREC and
  `DT_OTABLE_LFU_ATTRS` on the object table, else -EINVAL (other flags hit a
  NULL key(), a wild DORA_XATTR pointer, DORA_STATS overflow, or start/stop
  OI scrub); tgt_obd_idx_read() -EPERM unless nodemap off or a trusted admin
  nodemap with byfid_ops and no fileset; VARREC on an index with no
  rec_size() -EOPNOTSUPP (ZFS oops at this commit alone); rec_size() error
  returned, not truncated to __u16; `LFU_LINK_MAX` = 4096 - 16 -
  sizeof(lfu_rec) so a record fits one lu_idxpage (BUILD_BUG_ON); mdc copies
  only the pages the MDT sent, checks bd_nob_transferred; ii_version =
  LFU_WIRE_VERSION, mdc -EPROTO on another version or a swabbed reply
  (same-endian only, documented); LL_IOC_LFU_SCAN 'f' 221 -> 255 (221 was
  OBD_IOC_ECHO_MD); ldiskfs rec/xabuf allocated independently; DOIF_INDEX
  next()-after-load() comment; lfu.h include placement.
- **68817:** first paragraph rewritten; include order; no NULL checks
  before OBD_FREE; rec/xabuf allocated independently.
- **68818:** MDTs from `llapi_get_target_uuids()` on the mount fd (this
  mount's lmv, netlink without debugfs) instead of a debugfs glob by fsname;
  another worker's error stops the prefilter; posix_memalign aliasing;
  thread-count wording in code, man page and message; man ERRORS -EPROTO,
  -ENODATA, nodemap -EPERM; stale comments merged (spa_export gone);
  man3/Makefile.am order; message opening rewritten, design doc reference
  dropped; LU-20721 -> LU-20730 in comments and the ENOTTY message.
- **Verify:** own diff re-read (fixed a >80 comment line, a stale "has no
  version" comment, unbraced else, "page aligned" comments); checkpatch =
  originals (0/0/0 on 68816-68817, 68818 +0: man-page noise only); VM sweep
  3/3 build=0 warn=0.
- **Lab** (`~/rpcab.sh`, formats lfurpc, 3000 files + one file with 16 links
  of 251-char names; A = old tip 8618869c8f in ~/lustre-osdA, B = new tip;
  `/tmp/rpcab-{A,B}/results.txt`):
  - LL_IOC_LFU_SCAN of MDT0: A -E2BIG on the first call, 0 records, and
    llapi_scan_mount rc -7; B 1 call, 3099 records, link_big=1, and
    llapi_scan_mount rc 0, 3009 records.
  - nodemap active, default nodemap admin=0 trusted=0: B -EPERM; restored
    admin=1 trusted=1: B 3100 records. (A could not show it: -E2BIG first.)
  - pages past lsc_npages untouched in B (A not observable, same reason).
- **Lab round 2, the rest of it** (user: "Test on the lab"), all on the
  clone VM, arms: A/A2/A3 = old tip in ~/lustre-osdA, B*/C/guard* = new tip:
  - **Flag guard** (`~/flagab.sh`, lab-only sender patch in the build tree,
    `~/labpatch.py`, reverted and both trees rebuilt after): fixed build
    refuses all seven bad requests with -EINVAL -- no NOKEY, no VARREC, plus
    VARKEY, no DOIF_PARALLEL, plus DORA_XATTR, plus DORA_STATS, no
    DOIF_INDEX -- and `oi_scrub` status stays `init`; the good request is
    15 pages / 296 records. Unfixed build **served** the no-PARALLEL request
    (16 pages, 295 records) and `oi_scrub` went `init` -> `completed`: a
    client ran a full OI scrub. The crashing combinations were not run on
    the unfixed build on purpose.
  - **Wire version** (same script, `fail_loc=0x608` makes the server answer
    LFU_WIRE_VERSION + 1): client -EPROTO, and ok again once cleared.
  - **ZFS rec_size guard** (`~/zfsguard.sh`, FSTYPE=zfs): at 68816 alone
    (osd-zfs has no rec_size) the scan answers -EOPNOTSUPP and the MDS does
    not oops; at the tip it answers 15 pages / 295 records.
  - **DNE, 2 MDTs** (`~/dneab.sh`, 6000 files per MDT): both MDTs scanned,
    threads=1 and threads=2 both 12016 records (mdt0 6010, mdt1 6006); an
    INACTIVE MDT is refused at open (-ENODEV) with the message naming it.
    **Stop on error**, MDT0001 deactivated 3 s into the scan: A finished
    MDT0 (6010 records, 12.46 s) before returning -ENODATA, B stopped it at
    4805 (9.97 s). First attempt proved nothing (MDT0 had 500 files and was
    already done); and my own harness counted `total` unlocked, so the
    threads=2 totals were short until it used atomics -- per-MDT counters
    are single-writer and were always right.
  - **No debugfs** (`~/nodbg.sh`: private mount namespace, debugfs unmounted,
    an LD_PRELOAD shim refusing mount() so libcfs cannot remount it): A
    fails "cannot open /mnt/lfundb" (rc -2), B answers 306 records over
    netlink.
  - No LBUG or oops in dmesg across all of it; the fixed build is installed
    on the VM again.
- **ENOMEM pairing, PROVEN 09-17** (`~/enomem.sh`, lab-only injection
  `~/labpatch2.py` failing the xabuf allocation under fail_loc=0x608,
  reverted and both trees rebuilt after): unfixed answers **-E2BIG**, the
  rec_size() error truncated to __u16, so the real errno is lost; fixed
  answers **-ENOMEM**. Both recover once fail_loc is cleared (396 records,
  all with HAVE_LMA). The unfixed arm also showed
  `calls_with_unsent_pages_changed=1`, the untransferred-pages copy, against
  0 on the fixed one. The silent missing-LMA case inside one walk could not
  be reached: CFS_FAIL_CHECK fires on every call, so the walk always fails.
- **The four open Gerrit threads on the series, fixed (09-17 evening):**
  `fix-0915` = **1d403d0431** (tag `backup/fix-0917-cap`).
  - 68814, smatch "variable dereferenced before IS_ERR check 'obj'": out_obj
    tests `obj != NULL`, since dt_locate()'s error goes to out_env.
  - 68814, smatch "'dt' dereferencing possible ERR_PTR()": to decline --
    obd_lu_dev is checked non-NULL and lu2dt_dev() is a container_of.
  - 68818/adilger, capability: mdc_lfu_scan() asks CAP_DAC_READ_SEARCH, man
    page and commit message follow.
  - 68818/adilger, nodemap ID-offset filtering: to answer, not code; the
    server now refuses a scan unless the nodemap is trusted admin with
    byfid_ops and no fileset.
  - Verify: sweep 5/5 warn=0 err=0; checkpatch unchanged; RPC lab re-run on
    the new tip (3099 records, link_big 1, nodemap -EPERM then 3100).
  - **Replies POSTED 09-17** to all four and marked resolved (68814 and
    68818 now show 0 unresolved); the fixes themselves are unpushed.
- **man4 pages written (09-17):** `osd_ldiskfs.osd_itable_blockparse.4` in
  68812, `lfu.ring_size.4` and `lfu.batch.4` in 68814. man4 has no
  Makefile.am in the tree, so nothing to wire. checkpatch-man wants the
  title to match the filename, an AVAILABILITY release **and** a
  `.\" commit` line, and SEE ALSO ordered by section; all three pass now
  (one CHECK left on the 84-column .TH line, the standard section name).
  68814's message no longer says the pages are owed.
- **lfu repo scripts updated (76bbe74):** bench_osd_sweep.sh sweeps
  osd_itable_blockparse and takes DEV_SYSFS for inode_readahead_blks,
  lfu_noverify gone; 02-build/21-remount/26-ours-run check the new symbol;
  12-cold and 23-theirs-run keep the old names with a note, since they drive
  the out-of-tree lfu_par.ko.
- **`fix-0915` = 163d438831** (tag `backup/fix-0917-man4`): nine commits,
  checkpatch clean per commit, sweep green.

## 2026-09-17: OSD series 68810-68815, 44 lreview findings fixed (NOT pushed)

lreview on 68813/68814/68815 ($13.92, reports `docs/local/lreview-0917/markdown/`)
plus the 18 from 09-16 on 68810-68812. All checked by 3 agents against the
tree first. Branch `osd-fix-0917` = **afd3466f45** (was d678a006e7) in `~/lfs-carry-0915`
(tags `backup/fix-0917-pre-osd` = the old tip 8618869c8f,
`backup/osd-fix-0917-lab`). Only the 9 OSD commits changed; the 17 below
are untouched except 68163 (below). `fix-0915` moved to it the same day
(old tip = tag `backup/fix-0917-pre-osd`), and is checked out there.

- **Declined:** subject-line imperative on 68810, 68813, 68815 (house style).
- **68810:** `lfu_noverify` removed (scrub could spin on a priority item);
  a private iterator no longer touches `os_ls_fids`/`os_has_ml_file`;
  `inode_get_*_sec()`; `ooc_attr` allocated only under DOIF_ATTR (1 slot
  private); osd-zfs directory `la_size` = `doi_max_offset` (LU-15842);
  `osd_scrub_cleanup()` waits for private iterators instead of LASSERT.
- **68811:** readahead size is the fs's `inode_readahead_blks`
  (`lfu_ra_blocks` gone); cursor clamped to the walk; stops at the last
  used inode; kernel-doc placement; message rewritten.
- **68812:** nlink 0 always skipped (dtime rule was backwards); time decode
  sign-extends and adds epoch bits; LMA copied, re-checked and
  `fid_is_sane()` else iget; plug removed; `lfu_blockparse` renamed
  `osd_itable_blockparse`; scrub bookkeeping removed from the raw path.
- **68813:** inline xattr copied and re-checked (`osd_raw_xattr_copy()`),
  changed value goes to iget; zero-length value returns 0; counters count
  reads paid; ZFS needs DOIF_ATTR documented.
- **68814 (UAPI changed):** wire version 1, record 160 bytes, dead
  stripe/LMV/pool fields and reserved slots dropped, `LFU_INFO_PRIVATE` and
  the `private` param gone; new `LFU_REC_LMV_SHARD`, `LFU_REC_HAVE_PFID` +
  `lr_pfid_*`; padding zeroed; `read()` holds a mutex and checks reclen;
  next() error returned; stall is `wait_event_idle_timeout`; no global
  one-open limit; producer holds OSD + target obd refs and ends with
  -ESHUTDOWN on OBDF_STOPPING of either (the OSD alone is marked too late).
- **68815:** kernel (and client, 68818) backend no longer claims
  LAYOUT/LMV/LMV_FOREIGN/HSM; `lfs find --device` refuses layout and LMV
  options with -ENOTSUP (`--projid` still works; `-links` on a directory is
  undecided); shard and parent FID rebuilt; `scan_osd_kernel.so` in
  lustre.spec.in; include order and comment placement.
- **68816/68818:** the same record changes carried into
  `dt_otable_lfu_rec()` and `lustreapi_lfu_rec.h` (`struct scan_lfu_xattrs`).
- **Verify:** own diff re-read (found the pfid helper splitting a kernel-doc,
  fixed); checkpatch per commit = originals' noise, 2 long lines fixed;
  VM sweep 9/9 build=0 warn=0 (and 68814-68817 again after the last change).
- **Lab** (clone VM, `~/lfuab.sh`, formats `lfuab` on `/tmp/lfuab-*`, 100k
  objects; A = old tip, B = new tip; `/tmp/lfuab-{A,B}/results.txt`):
  - time decode, 2040 / 1960 file: A raw 6503984896 / 3979376896 vs iget
    2209017600 / -315590400; B raw == iget, 0 of 100306 records differ.
  - padding: A 10208 records with nonzero pad bytes, B 0.
  - two scans (MDT held + OST): A `EBUSY`, B both complete.
  - `--stripe-count 2` / `! --pool nosuch` on the mounted MDT: A 0 / 100216
    hits exit 0, B -ENOTSUP; `--projid 0` rc 0 in both.
  - OST0 `--fid2path`: A 0 names, B 5 (the 5 written files; 124 never
    written objects have no parent FID, same in both).
  - nlink-0 inode with dtime (debugfs on a copy): A raw path returns it,
    B skips it; iget skips it in both.
  - B only: 4 readers on one fd read 100306 == emitted, no bad records;
    umount under a stalled reader returns in 0s and the reader gets
    -ESHUTDOWN (first B run, OSD flag only: umount waited 21s). A not run
    (predicted LASSERT).
  - no LBUG/oops/hung-task in dmesg; `/tmp/lustre-*` fixture untouched.
- **Not proven in a lab:** readahead clamp and cap,
  DNE shard naming (needs 2 MDTs), the xattr race fixes (race window).
- **68163 ZFS device scanner directory size, FIXED later the same day:**
  `so_size = doi.doi_max_offset` for a directory, message says so;
  `osd-fix-0917` = **afd3466f45** (tag `backup/osd-fix-0917-zfsdir`; before:
  `backup/osd-fix-0917-pre-zfsdir` = d678a006e7); tree delta is the 5 lines;
  checkpatch unchanged; 68163 utils and the tip build warn=0. ZFS lab
  (`~/zfsab.sh`, FSTYPE=zfs, dirs of 5000/300/1 files, `/tmp/zfsab-{A,B}`):
  client stat 761856/40960/16384; A kernel stream and device scan both 2/2/2;
  B both equal the client's sizes. This also proves 68810's osd-zfs fix.
- **Left open:** lfu-repo
  `tests/bench_osd_sweep.sh` and `tests/lab/02-build.sh`/`21-remount.sh` use
  the removed `lfu_*` params (old measurements, not updated).
- **VM:** arm B (new tip) is installed; the old 2.19 install is in
  `~/installed-lustre-backup-0917.tgz`. Nothing mounted, VM still up.
- **68816-68818 lreview:** done, see the 09-17 afternoon entry.
- **CI actions 09-17:** LU-20276 (osd-zfs OOM, sanityn) linked and single
  session retests requested for 68582 PS2 and 64945 PS5
  (review-dne-zfs-part-5); BUILD posted on 68414 PS8 (Maloo never ran on
  Andreas's 09-14 rebase).

## Start here (end of 2026-09-16) -- SUPERSEDED by the 09-17 entry above

**Nothing is running.** VM shut down. Pushed today: 68094 PS20,
68095/68156/68157 PS21 (on 68231 PS8); replies posted to their 15 AI
threads; 68417 linkno decline posted.

1. **The stack:** `fix-0915` = **8618869c8f** in `~/lfs-carry-0915`, 26
   commits; first four = 101891803c (as pushed). Everything below this
   entry is folded in: lreview on 68095/68159 and on 68415-68420, 68726,
   68727 (all findings fixed or declined), the rename routing, the
   changelog-user and restarted-log fixes. No commit message or file
   mentions lfind.
2. **Watch** the four pushed changes: autotest, Maloo, AI review, Andreas.
3. **Replies owed after each push:** `docs/local/replies-series/<change>-<ps>.json`
   (39, post only once that change is pushed).
4. **Artem (09-16):** asked where the series starts and whether the old
   68158-68818 (on 68157 PS19, Sep 11) are planned. Told: start = 68231;
   holding the rest is Andreas's plan; 68160 PS20 on Gerrit is the lfind
   version, locally it is "lfs: find over a target, with --device" under
   the same Change-Id (keep, don't abandon). Artem: "probably some troubles
   with pushing patches, don't worry, take your time".
   **Undecided, user's call:**
   - post a comment on 68160 that PS20 is outdated (no patchset);
   - mark 68158-68818 WIP on Gerrit;
   - update LU-20611 (title still "Utils: lfind, the server-side find
     command..." and a description arguing against lfs find): draft title
     "Utils: lfs find over a Lustre target, read from its device" and a
     Jira-markup description were written in the session (not saved);
     jira CLI credentials not yet checked;
   - abandon candidates OUTSIDE LFU: 67052 (LU-20119 dbg, fortestonly),
     65388 (LU-20147, CR-1 since 04-24), 65120 (LU-20084, V-1 since 04-19).
5. **Open, not urgent:** --since parent directories (option B) is only
   documented; 68340 still needed (series covers only half of it).
6. **lreview on the OSD series, 3 of 9 done (user limited it for
   tokens):** 68810 (6 findings, high, $5.03), 68811 (6, low, $2.63),
   68812 (6, high, $4.14); reports in `docs/local/lreview-0916/HEAD_{b446b3d,5ad3170,beb8d09}_*.md`.
   NOT verified yet. Defect claims to check first: 68810 os_ls_fids used
   from a consumer thread under DOIF_PARALLEL; i_atime/i_mtime direct use
   on kernels with inode_get_*_sec(); stray lfu_noverify. 68811 readahead
   cursor not advanced across bitmap gaps. 68812 dtime check possibly
   backwards, unlocked in-inode xattr read, extra-time decode not
   sign-extending like ext4_decode_extra_time(). 68813-68818 not run.

## 2026-09-16 afternoon: lreview rerun, first four PUSHED

`fix-0915` = tag `backup/fix-0916-pushed` (6653785f90)
in `~/lfs-carry-0915`. The earlier entry below is superseded on "NOT
pushed" and "Push: held" (the user chose to push the four).

- **lreview 68095 ($3.59, 4 low):** 3 fixed, 1 declined.
  - `--links` added to the message's list of predicates that lost a
    subtree off Lustre.
  - sanity 56El's descent check is now `-type f --links 1`. VM lab
    (`~/lr2-ab-*`, A/B/A/B): old `-type f` passes on 68094 and 68095
    alike; the new check FAILS on 68094 (exit 1, 0 files, EPERM) and
    passes on 68095.
  - The always-true `want & LLAPI_SCAN_MDT_MASK` level removed from
    `cb_find_init()`. RPCs rechecked at the tip: 6007/8008/6207/8208 vs
    6005/8007/6206/8208 before, same answers (first-run noise of 1-2).
  - Declined: `projid = 0` -> `DEFAULT_PROJID` at 68095; 68157 makes that
    exact rename and its message lists it.
- **lreview 68159 ($6.49, 4, medium): all real, ALL FIXED later the same
  day** (`fix-0915` = 3835f8029e, tags `backup/fix-0916-pre-159` /
  `backup/fix-0916-159`; 68159 not pushed). Reports in
  `docs/local/lreview-0916/`. Only 68159's patch changed (range-diff); the
  pushed four keep 101891803c. Sweep 26/26, checkpatch identical.
  - #2 `%Lo`: `count >= LLAPI_LAYOUT_INVALID` skips to the next component
    instead of `count == LLAPI_LAYOUT_DEFAULT` ending the walk. VM lab
    (`~/lo-ab-*`, A/B/A/B, tip arms): `-E 1M -c 1 -E eof -c -1` unfixed
    1023 bytes of "?,", 510 stderr lines, no "|end"; fixed `[1]|end`, no
    stderr. Middle `-c -1` (`-E 1M -c 1 -E 64M -c -1 -E eof -c 2`): unfixed
    floods, fixed `[0][?,?]|end`. Plain, `-c -1`-first-and-written, and
    default-count-middle files identical in both arms. (`-c 0` is not a
    valid setstripe, so a stored DEFAULT middle count was not built.)
  - #1: the four comments and two message paragraphs now say what the code
    does, not what earlier patchsets did.
  - #3: the fp_mdt_index comment names OBD_NOT_FOUND.
  - #4: llapi_find_device.3 no longer says OST objects are named from
    trusted.fid (no commit in the stack does that); the message says an OST
    object with no LMA prints as obj:ID.
  The list below is the finding text as reported:
  1. Message and comments narrate earlier patchsets ("Before, such
     objects took the no-layout path", find_lmm_fits(), find_device_cb(),
     find_rec_to_lmd()).
  2. DEFECT: `printf_format_ost_indices()` catches only
     `LLAPI_LAYOUT_DEFAULT`; an uninstantiated `-c -1` component gives
     `LLAPI_LAYOUT_WIDE_MIN + n`, so `%Lo` fills the buffer with "?," and
     loses the newline, and `goto format_done` drops later components.
  3. The fp_mdt_index comment says "a 0 there" where the gate tests
     OBD_NOT_FOUND.
  4. llapi_find_device.3 says OST objects are named from trusted.fid, which
     only 68288 reads.
- Verify: sweep 26/26; checkpatch identical on all 26 after shortening one
  81-column comment; the four Change-Ids match; Gerrit's PS19/PS20 were
  exactly this morning's commits.
- **PUSHED** `101891803c` -> 68094 PS20, 68095 PS21, 68156 PS21, 68157
  PS21, on 68231 PS8 (unchanged). Replies posted to all 15 AI threads on
  PS19/PS20; audit: 15 replied, 0 open.
- **Next:** watch the four's CI and AI review; the other 21 still wait for
  the four to land (68159's lreview findings are fixed, see above).
- **lreview on 68415-68420, 68726, 68727 (09-16, $31.89, 30 findings):**
  verified by 3 agents, triage in `docs/local/lreview-0916/TRIAGE-upper8.md`
  (28 real or partly real, 2 decline candidates, none fixed later).
  - **68415 resolve open, FIXED** (`fix-0915` tag `backup/fix-0916-open`,
    pre-fix tag `backup/fix-0916-ai39`). `scan_cl_resolve()` opened a
    regular file O_RDONLY for the glimpse; that is an MDS open, so with an
    OPEN-mask user it wrote CL_OPEN/CL_CLOSE into the log being read. Now
    only the O_PATH open by FID, and `scan_cl_mdt_stat()` statx()es without
    AT_STATX_DONT_SYNC (revalidate, plus a glimpse when want is 0 or names
    SIZE/BLOCKS/MTIME); otherwise it takes the lazy size with DONT_SYNC and
    leaves mtime unset. Man page, comments and message updated; also the
    `.IR lfsr_stx.stx_uid : the` typo. gcc 11 on the VM flagged `st` as
    maybe-uninitialized (the host did not): zero-initialized.
  - Lab (VM `~/open-ab2-130901`, a C harness calling llapi_scan_changelog()
    with RESOLVE, user registered -m ALL, fresh files each round, A/B/A/B):
    unfixed want=0 resolve wrote **22 OPEN / 11 CLOSE** (round 1) and **44 /
    22** (round 3); fixed wrote **0/0** in every run. Sizes strict and uids
    identical in both arms. `lfs find --changelog --resolve` does NOT use
    LLAPI_SCAN_CL_F_RESOLVE (it resolves through llapi_scan_fid()), so the
    bug hits only API callers and 157d.
  - 68415 #3 (stale owner) did not reproduce in either arm: a chown on a
    second client mount was seen by both. Covered anyway by the revalidating
    statx.
  - Sweep 26/26, checkpatch identical. First four still 101891803c.
- **Triage round 2 (09-16), `fix-0915` = db67e21d36** (tags
  `backup/fix-0916-pre-triage`, `backup/fix-0916-triage`), one rebase over
  the 8 commits. First four still 101891803c.
  - 68415: "Nothing in lustre/tests drives it" paragraph removed;
    "unclosed" -> "uncleared"; 157d gated on MDS >= 2.17.0 (the user
    lookup, 5b85a4eb75, first tag 2.17.0).
  - 68416: llapi_scan_fid.3 says what lfsp_filter sees and that a shard
    FID answers -ESTALE where detected; dropped the false claim that
    llapi_scan_changelog() merges through it.
  - 68417: three comments say the why without history.
  - 68418: a nameless record under --changelog --resolve tests each link's
    name (fss_live_name), and a recorded name that failed on an in-root
    path skips the link loop; "-printf and --ls" in the refusal; --ls in
    both man lists; llapi_find_since.3 no longer names scan_cl_mode().
  - 68419: find_cookie_read() opens O_NONBLOCK and refuses a non-regular
    file before reading; ferror() -> -EIO (documented); -ENAMETOOLONG text
    fixed; lfs-find.1 says to remove FILE to accept a purge gap (moved
    with the --since-cookie section 68420 relocates).
  - 68420: man and 160ab comment say the name carries within one burst;
    message opens with the tests.
  - 68726: scan_batch_filter() returns -ECANCELED once closed; test12
    regression; test14 second calls wait for an armed flag; close overlap
    reworked (a filter that naps on every object, close only once the scan
    is inside it) because the fix made the old setup unreachable (0/8).
    Message no longer narrates the ASan history.
  - 68727: two comments (param_callback over-long path; "less trailing
    slashes"). #1 (symlink start point off Lustre) DECLINED: on Lustre the
    answer is unchanged, and keeping the slash for a symlink brings back the
    -name mismatch the trim fixed.
  - Lab (VM `~/tri-ab-132554`, A = pre-triage, B = fixed, fixed test
    binary with each arm's library via LD_PRELOAD):
    - test12: A fails "the filter saw all 6 objects after an early close"
      (0.29 s), B passes (0.03 s). test14: both arms 8/8 on both overlap
      cases after the rework, no failures.
    - `--since-cookie /dev/zero` and a FIFO: A killed by timeout at 10 s
      (exit 124), B exit 22 in 0.02 s "is not a regular file".
    - hardlink a/f = b/g, log cleared, one append (MTIME+CLOSE, no name),
      link 0 = a/f: A `b -name g` [] and `b -name f` [b/g]; B `b -name g`
      [b/g] and `b -name f` []; `a` queries identical.
  - Sweep 26/26 (before the last two comment/man-only line wraps);
    checkpatch identical to the pre-round run (checkpatch reads man pages
    from the worktree tip, so a man-line note shows on every commit).
  - The last two triage items and option B were done the same day; see
    below.
- **Rename gap, option A (user's choice), `fix-0915` = a6b4b50127** (tags
  `backup/fix-0916-pre-rename`, `backup/fix-0916-rename`). Fixed in the
  library (68415): `scan_cl_rec_fids()` says which objects a record is
  about -- the target, else for CLF_RENAME the moved object (cr_sfid); a
  rename over a name is about both and is delivered/coalesced for each;
  a CL_MARK about none. `scan_cl_event()` delivers one record per object,
  `scan_cl_object()` coalesces under each. llapi_scan_changelog.3's
  rename paragraph and the 68415 message rewritten (the API contract
  changes: lfsr_fid is no longer absent for a rename to a new name).
  New llapi_scan_changelog_test test8. 68419's filter comment reworded.
  68420 adds sanity 160ae (mv to a new name and over a name; --since
  under the target dir, --changelog -name) and its Test-Parameters.
  Option B (parent directories as --since candidates) NOT done: document
  or implement later, user's call.
  - Lab (VM `~/ren-ab-135150`, A = pre-rename, B = fixed): test8 on A
    fails "renamed to a new name: 0 records in event mode, 0 in object
    mode"; the whole changelog test suite passes on B. `lfs find a
    --since 1h -type f`: A [] ("1 of 1 changed objects no longer exist"),
    B [a/g a/old]. `--changelog all -name g`: A [], B [a/g]. On a clean
    log B lists g, the replaced object by FID, and old.
  - Sweep 26/26, checkpatch identical to before the change. First four
    still 101891803c.
- **Last triage items (09-16), `fix-0915` = 9a7778d85f** (tags
  `backup/fix-0916-rename` before, `backup/fix-0916-last2` after):
  - 68415 #5: `llapi_changelog_start_user()` (and its MDS-side user
    lookup, which needs a 2.17.0 MDS and fails for a plain register,
    LU-20647) is used only when `sc_type_mask` is set; mask 0 now means
    every type, and `sc_user` is then only for clearing. Header, man page
    and message updated; the 157d MDS gate added earlier was removed again
    (no lookup, so not needed).
  - 68419 #3: `find_cl_oldest()` became `find_cl_first(mdt, startrec)`;
    for a non-empty log the check also probes from the anchor and refuses
    -ESTALE when nothing is at or after it ("its changelog was restarted").
    lfs-find.1, llapi_find_since.3 -ESTALE and the message say so, and that
    a restarted log grown past the anchor cannot be seen from indexes.
    160ac gains a cookie rewritten to index 999999999.
  - Option B: documented only. lfs-find.1 --since says a directory counts
    as changed only when a record is about the directory itself.
  - Lab (VM `~/l2-ab-140429`, A = backup/fix-0916-rename, B = fixed):
    - plain `changelog_register` (cl1, no mask/name), test6 (_CLEAR):
      A fails "cannot set changelog filter: No such file or directory";
      B passes, "cleared through 22".
    - real restart (30 files, cookie, deregister every user, umount and
      mount the MDT, re-register, 3 files; log 1..6): A exit 0 with no
      output (6 records silently skipped); B exit 116, "holds records but
      none at or after 66 ... its changelog was restarted".
  - Sweep 26/26; checkpatch identical after wrapping one 81-column line.
    First four still 101891803c. Nothing pushed.
- **Unreplied AI threads across the series, checked 09-16 (39 on 10
  changes, all on current patchsets; 3 agents + my spot check):** 36 were
  already fixed in `fix-0915`, 2 are moot (68160: lfind.c gone, conf-sanity
  --search line rewritten), 1 was not: 68418's CL_MARK comment rewording
  had landed in 68419; moved down into 68418. Also fixed on the way:
  68416's @mnt_fd comment (the mount-root reason now sits by the fd, the
  local-variable comment names only the statx and opens) and its
  trailing-slash message paragraph; two past-tense phrases in 68419's
  message; 68420's second paragraph reads "160ab also covers". Left as
  they are: 68415's test has no sc_padding / short ss_size case, and
  68288 --fid2path on an MDT with an empty map looks names up through
  the mount. `fix-0915` = 4ebc7709a3 (tags `backup/fix-0916-pre-ai39`,
  `backup/fix-0916-ai39`), first four still 101891803c; sweep 26/26,
  checkpatch identical, message filter left trees and trailers identical.
  68417 `7d9d284f` (linkno 1) decline is POSTED. The other 39 replies
  (68417's four included) are in `docs/local/replies-series/<change>-<ps>.json`:
  post each change's file only AFTER that change is pushed.

## 2026-09-16: AI review of the pushed four, 15 threads (NOT pushed)

`fix-0915` = **04d19748b9** in `~/lfs-carry-0915`. Backups
`backup/fix-0916-{pre-ai,prefold,pre-xform,pre-msgs}`. The bottom four now
have new hashes: they need a new patchset when the series is next pushed.

- **Fixed (13):**
  - 68094: `tv_nsec` is always 0 today (llite fills only `tv_sec`), and the
    man page and the lustreapi.h comment now say so. `static_assert` that the
    `ends[]` table reaches `sizeof` the struct, in `scan_param_whole()` and
    `scan_cl_param_whole()`. Proven: an appended field fails the compile
    for both tables (scratchpad `sa/`).
  - 68095: 56El's trap falls back to `umount -l`; `get_projid()` passes
    `rc` to `llapi_error()` and does not print strerror twice.
  - 68156: message drops "inode generation" and "read from trusted.fid"
    (neither is in the patch); the man page says ldiskfs orphans count in
    `ss_skipped`; `enum llapi_scan_class` values written out; conf-sanity
    300-304 moved after test_250 (a move only: sorted lines identical at
    the tip).
  - 68157: message and `find_get_projid()` comment no longer describe the
    `-ENOTSUP` decode that only arrives in "run find over a device scan";
    two stale `cb_find_init()` names; the double blank line.
- **Declined:** 68094 sanity.sh:21194 gate. v2_17_58 is tagged and is an
  ancestor of our base; the AI's tree lacked the tag.
- **68095 liblustreapi_pfind.c:2643, fixed (user chose "restore the early
  reject"), `fix-0915` = 04d19748b9** (tags `backup/fix-0916-pre-lmv`,
  `backup/fix-0916-lmv`). `scan_rec_gather()` is split into
  `scan_rec_gather_lmv()` + `scan_rec_gather_rest()` (the wrapper stays for
  the scanners); `find_lmv_rejects()` holds the `--mdt-count`/`--mdt-hash`/
  `--hash-flags`/`--foreign` rejects, and `cb_find_init()` runs it between
  the two steps. The `! --foreign` accept still waits for the stat (so
  -printf sees this object). 68157 moves the smaller block unchanged;
  "run find over a device scan" adds the late `find_lmv_rejects()` call in
  `find_decide()` for callers that did not walk. 68095's message says so and
  lost the "one more ioctl" bullet.
  - Lab on the clone VM (`~/lmv-ab-063225/`, lfst fixture NOFORMAT=1, 1001
    unstriped dirs + 201 files, LD_PRELOAD arms proven by trace, A/B/B/A x2;
    each case gave the same count in all 8 runs, except one 8008 in the
    very first run): rejecting queries `--mdt-count 2`,
    `--mdt-hash crush`, `--foreign` cost **8007 / 8007 / 8208 MDC RPCs
    unfixed, 6005 / 6005 / 6206 fixed** (2 per rejected dir). Accepting
    `--mdt-count 0`, `! --foreign`, `-type d`: same RPCs both arms. Every
    answer md5-identical across arms. VM shut down after.
- Verify: fold tree identical to the pre-fold tip (13 fixes); sweep 26/26
  again after the LMV change (run in
  `lustre-scanfid`, the configured tree); checkpatch identical on all 26;
  message filter left trees and trailers identical.
- **Push: held.** Plan: wait for Andreas's review of 68094 PS19 /
  68095-68157 PS20, push the four once with his comments; if he is silent
  a day or two, ask him on 68095 whether he wants the regression fixed in
  place or as a follow-up. Replies to all 15 AI threads drafted in
  `docs/local/replies-0916/<change>-<ps>.json` (full ids, none ranged);
  post with `gerrit review <change>,<ps> --json` only AFTER the push.

## 2026-09-15: carry, lreview on the next five, first fixes (NOT pushed)

Worktree `~/lfs-carry-0915`. The clone VM (192.168.122.10) was started
for the 68160 A/B and shut down again, nothing mounted; its arms
`~/lustre-sw-{a,b}` and logs `~/sw-ab-*`, `~/sw-cs300-*` stay on it.

- **Carry done.** `carry-0915` = **49aacec41c** (tag `backup/carry-0915`):
  the 17 upper commits cherry-picked onto `fix-first4` (57b3fbb2c4), so
  yesterday's fixes are in. 68616/68617 left out, as Andreas wants. Tree
  bf0fbe0031 = d3a2e2e903 + the fix-first4 diff - 68616/68617 (proven with
  a scratch index). Range-diff 17/17 identical, checkpatch identical, sweep
  26/26.
- **lreview, one at a time:** 68158 1 ($1.92), 68159 6 ($3.95), 68160 6
  ($2.55), 68163 8 ($4.10), 68288 5 ($3.22) = $15.74. Every finding
  checked against the tree; all real except 68160 #3 (lfs-only fields in
  `find_param`), which the user said to skip.
- **Fixed on `fix-0915` = 0865b275a2** (tag `backup/fix-0915-prefold`
  before the fold): 68159 - `-printf %+5p`/`% 5p` got past the `%p`
  refusal, `--mdt` early exit like `--ost`, a V3/SPECIFIC composite entry
  must be >= 48 bytes; 68160 - a `--local`/`--fsname` sweep skips targets
  of the wrong type for `--ost`/`--mdt` (it broke on the MDT's ENOTSUP and
  never read the OST), `--fsname` uses `llapi_name_validate()`. Tree
  0006474bd8 = fixups on the tip. Lifted A/B (scratchpad `lift0915/`): all
  three pfind.c fixes change the answer only where intended. Sweep 26/26,
  checkpatch identical (68159/68160 check a few more lines). Commit 12
  (68417) shows `!` in range-diff: context only.
- **Later the same day, `fix-0915` = 3031e31a66** (still worktree
  `~/lfs-carry-0915`, nothing pushed):
  - 68288, all 5 fixed (fold tag `backup/fix-0915-pre68288`): `LMV_SHARD`
    widens to `LMV`; `-printf` with `--paths`/`--fid2path` refused
    (lfs-find.1 and llapi_find_device.3 say so); the fid2path error names
    the mount only when the lookup used it; two comments. Lifted A/B
    (scratchpad `lift68288/`): widen and refusal change only the intended
    cases. Sweep 26/26, checkpatch identical.
  - Messages of 68158, 68159, 68160 and 68288 rewritten in simple English,
    describing each patch as it is now (38, 101, 58, 109 lines; were 50,
    197, 67, 267). Long versions at tag `backup/fix-0915-long-msgs`.
    filter-branch, messages only: all 26 trees identical, Change-Ids and
    trailers intact, the pushed bottom four keep their hashes.
- **68163 docs and comments, `fix-0915` = 66aeb6c766** (fold tag
  `backup/fix-0915-pre68163`): llapi_scan_device.3 and lfs-find.1 state
  the real routing rule ('/' = device path that must exist; a relative
  name is a device only if it is a block device or regular file; any
  other relative name is a dataset); the message paragraph says the same;
  the stale "empty pool name" comment; the `spa_export()` comment says it
  is EROFS under SPA_MODE_READ and the import lasts until kernel_fini();
  lustre/tests/Makefile.am explains -Wl,-u in place. Trees identical
  through fold and message filter, pushed four intact, sweep 26/26,
  checkpatch identical.
- **68160 sweep fix proven on the clone VM** (`~/sw-ab-125804/`): arms
  `~/lustre-sw-a` = 49aacec41c (unfixed) and `~/lustre-sw-b` =
  3031e31a66 (fixed), each loading its own liblustreapi (LD_PRELOAD,
  traced) and its own hand-built plugin (strace). `lfst` fixture mounted
  with NOFORMAT=1 (MDT + 2 OSTs), A/B/A/B, rounds agree:
  - `--local --ost lfst-OST0000 -type f`: unfixed exit 95, 0 lines,
    stopped at the MDT; fixed exit 0, 33 lines. The 33 are all in the
    plain `--local` answer and equal a direct `--device /tmp/lfst-ost1`
    scan.
  - `--local --mdt lfst-MDT0000 -type f`: unfixed 2 lines then exit 95
    on OST0000; fixed 2 lines, exit 0.
  - `--local -type f`: 100 lines, exit 0, both.
  Cosmetic, not fixed on purpose: the fixed sweep still prints the
  "# lfst-OST0001" header for an OST that the library's --ost check then
  skips. Hiding it means copying the name/index/negation matching of
  find_tgt_index() into lfs.c for one stderr line.
- **conf-sanity 300 check, folded into 68160: `fix-0915` = 3429973fc8**
  (tag `backup/fix-0915-pre-cs300`). Before `stopall`, where mds1 and
  ost1 are one ldiskfs node: `--local --ost <ost1>` and `--local --mdt
  <mds1>` must exit 0 and name no target of the other type on stderr.
  68160's message says so. Not run in the framework (its gate is
  2.17.58, the VM's modules are 2.17.57); emulated on the VM with the
  same two commands and four assertions (`~/sw-cs300-*`): unfixed arm
  fails all four, fixed arm passes. Trees identical through fold and
  message filter, pushed four intact, checkpatch identical.
- **68163 zpool.cache fix, proven on the clone VM, `fix-0915` =
  a27b5439d6** (tag `backup/fix-0915-pre-zfsfix`; the fix was branch
  `zfsfix-0915` = 2db477a902 before the fold). `spa_config_path = ""`
  before the first `kernel_init()`, so no cached pool skips the EBUSY
  checks (ZFS 2.2.11 source: `spa_config_load()` stops at the failed
  stat; `spa_write_cachefile()` returns without SPA_MODE_WRITE).
  Lab `~/zs-ab-132738/`, `zfst` on file vdevs in /tmp/zfslab, arms
  `~/lustre-zu` (unfixed) and `~/lustre-zf` (fixed), plugins told apart by
  `nm | grep spa_config_path` and strace:
  - kernel-held MDT pool listed in zpool.cache, twice: unfixed exit 121
    EREMOTEIO (MMP check stopped the open); fixed EBUSY "in use".
  - control, kernel-held OST pool not cached: both EBUSY.
  - positive control, all exported, `--search`: both 51 lines, identical.
  - pool ONLINE after; zpool.cache restored to 0 bytes; VM shut down.
  68163's message says the scan loads no zpool.cache (measured result
  only). Build note: `--disable-modules --with-zfs=<src>` fails in
  upstream `libmount_utils_zfs.c`; built the three targets by name.
  Trees identical through fold and message filter, pushed four intact,
  checkpatch identical, sweep 26/26 (this host cannot compile
  libscan_zfs.c; the VM build did).
- **68163 ARC cap and spa_export removal, measured and folded: `fix-0915`
  = 0c539f3929** (tag `backup/fix-0915-pre-zfsopt`; was branch
  `zfsopt-0915` = fac9b7db21). Lab `~/zopt-135719/`, arms `~/lustre-zf`
  (base) and `~/lustre-zn`:
  - `zfs_arc_max = 256 MB` alone is ignored by libzpool ("ignoring tunable
    zfs_arc_max"): userspace `arc_init()` sets the min to half the max. zdb
    also sets `zfs_arc_min = 2ULL << SPA_MAXBLOCKSHIFT`; so does 68163 now.
  - 1.2M objects (431 MB metadata), alternated, 12 answers identical:
    peak RSS base 434-459 MB, capped 226-347 MB; wall time within noise
    (cold median 13.20 vs 12.82 s, warm 12.51 vs 12.94 s).
  - Export: an LD_PRELOAD shim showed all 6 base `spa_export()` calls
    return 30 (EROFS). Without them, repeated and concurrent scans in one
    process give identical rc and record counts.
  68163's message has one paragraph on both. Trees identical through fold
  and message filter, pushed four intact, checkpatch identical, sweep
  26/26. VM shut down; `/tmp/zfslab` (2.3 GB) left on it.

## Tomorrow: start here (end of 2026-09-15)

**Nothing is running and nothing was pushed today.** The clone VM is shut
down (test builds `~/lustre-{sw-a,sw-b,zu,zf,zn,r2}`, logs `~/dne-shard-*`,
`~/zfs-race-*`, `~/zopt-*`, ZFS vdevs in `/tmp/zfslab` stay on it).

1. **The stack:** `fix-0915` = **d0e1be9460** in `~/lfs-carry-0915`, 26
   commits on 68231 PS8; the bottom four are the ones pushed 09-14 and keep
   their hashes. 68158-68288 and the upper 17 carry today's fixes, two
   lreview rounds and simple-English messages. Backups: `backup/carry-0915`,
   `backup/fix-0915-*` (one per fold).
2. **Push order unchanged (Andreas):** wait for 68231, 68616/68617 and the
   first four to land, then push the next few. Ask before any push.
3. **Watch Gerrit** for the first four's AI review and Maloo votes; carry
   any findings into `fix-0915` the same way (fixup + autosquash, tree
   check, sweep, checkpatch).
4. **Open, not urgent:** `/.lustre` and `/.lustre/lost+found` print under
   `--paths` though a client walk hides them (older behaviour); zdb-style
   ARC numbers only measured to 1.2M objects.
5. **Reply owed by the user:** 68414 PS6 COMMIT_MSG:74 (Test-Parameters).

## 2026-09-15 evening: lreview rerun on 68163, 68159, 68160, 68288 (NOT pushed)

`fix-0915` = **d0e1be9460** (tag `backup/fix-0915-pre-r2`), worktree
`~/lfs-carry-0915`. lreview $13.83, 13 findings, all checked against the tree.

- **Fixed, each proven or checked:**
  - 68288 #3 (defect): `--paths` printed a striped directory's shard as
    `/sdir/[0x...]:0`. Paths now ask for `LLAPI_SCAN_LMV_SHARD`, and a shard
    counts as nameless. DNE lab `~/dne-shard-150558/` (MDSCOUNT=2, ldiskfs,
    `lfs mkdir -c 2`, MDT0 image scanned after stop), 2 rounds: unfixed 1
    shard name per run, fixed 0; the 10 files in the striped dir named by
    both; nameless 5 -> 6. `/.lustre` and `/.lustre/lost+found` print in
    both arms (older behaviour, not this round).
  - 68163 #1: two threads opening one exported pool raced to EEXIST.
    `spa_import()` EEXIST is now success. `~/zfs-race-150709/`, 40 rounds on
    `zfst-ost1/ost1` + `@race`: unfixed failed one open in every round
    (rc -17), fixed 80/80 opens rc 0.
  - 68160 #1: `lfs_find_is_device()` checks every path, not only the
    first. 68160 #2: lfs-find.1 says only `--device` or a block device
    needs nothing mounted.
  - 68288 #5: pre-pass skips were dropped; `struct scan_prepass` gets
    `pp_skipped` and `llapi_find_device()` warns (public stats untouched).
  - 68159 #2: prefilter comment claimed `-uid` was settled (it is not; the
    undecided count can include such objects). 68159 #3: llapi_find_device.3
    says `--mdt` leaves `fp_mdt_indexes` allocated, as a walk does.
  - Messages: 68159 "numeric index"; 68288 history phrases, the wrong
    `ret = CMD_HELP; goto out` quote, and the "map used when the target
    cannot answer" claim (also fixed in the code comment).
- **Declined:** 68288 #6 (`-EINVAL` for bad arguments is documented; an API
  change); 68288 #4's lfs-find.1 addition (DNE namelessness already stated);
  68160 #3 (`find_param` fields; user skip).
- **Checks:** each fix added by its intended commit and absent from its
  parent; trees identical through fold and message filter; pushed four
  intact; sweep 26/26; checkpatch identical. VM shut down.

## Tomorrow: start here (end of 2026-09-14)

**Nothing is running locally.** The clone VM (192.168.122.10) was started
for the A/B and shut down again at the end of the day; `~/lustre-ab0914`
is on it.

1. **Watch the four pushed changes** (68094 PS19, 68095/68156/68157 PS20,
   on 68231 PS8). Testing started 09-15 01:00. hpdd-checkpatch left 5
   style notes (81/82-column lines, fallthrough comment, else after
   return) on 68095/68156/68157; not checked line by line.
2. **Replies owed by the user:** 68414 PS6 COMMIT_MSG:74 (Andreas removed
   the Test-Parameters line himself; he also edited PS6->PS8, rebased; our
   local 68414 and 68413 copies are stale, start from Gerrit).
3. **Open on purpose:** 68095 PS18 `--name` trailing slash (fixed in
   68727, not pushed) and 68156 PS16:730 stats request mask (follow-up).
4. **Andreas's plan:** let 68616/68617/68231 land; push the next few of
   each series only as the earlier ones land. This round's fixes (lreview
   on the first four) must be carried into `lu-upper-onto-lfs` first.
5. **lreview findings not acted on:** 68616 and 68617 wording (hold for a
   refresh), 68095 56El `-type f` check strength and `const` params.

## PUSHED 2026-09-14: the first four, on 68231 PS8

`git push review 75f2669c34:refs/for/master` from `~/lfs-fix-0914`
(branch `fix-first4`, messages rewritten in simple English; long ones at
tag `backup/fix-first4-long-msgs-0914`): 68094 PS19 `f9ed71ab6d`, 68095
PS20 `34350af72b`, 68156 PS20 `5e28565a51`, 68157 PS20 `75f2669c34`;
68231 stays PS8. 68616/68617 untouched, the rest of the series not pushed
(its fixes from this round are NOT in `lu-upper-onto-lfs` yet). Replies:
`replies-r3/68094-18.json` (2) POSTED 09-15 00:56 on PS18, threaded,
resolved (gate now 2.17.58).
Still-open older threads on these four (68094 PS16 x5, 68095 PS18 --name,
68156 PS9/PS16 x9) were not re-checked in this round.

## Earlier (2026-09-14): rebased onto master, not pushed

Asked on Gerrit: sanity-sec test_27ad times out on the chain because our base
(`5afbab284e`, 08-19, the commit that *added* 27ad) predates the LU-20087 hang
fix `14cf8275e2` (08-22). Rebased the round-3 stack onto `review/master`
`47638add78` (136 commits later); the refresh was owed anyway.

- Tips: `lu-upper-onto-lfs` = `rebase-0914` = **d3a2e2e903** (29 commits),
  `lu-20637-names-onto-lfs` = `rebase-0914~17`; `lower-on-68231` =
  **ad791bd965** (first four fe7af7add3 b4a683ed4e 06e1c6adc3 88ef20daa0).
  The gate-bump filter had written sanity.sh/conf-sanity.sh as 100644;
  restored to 100755 (lreview caught it), backups `backup/*-pre-mode-0914`. Backups
  `backup/{upper,lower}-pre-rebase-0914`, `backup/upper-pre-gate-0914`;
  unnormalized rebase `rebase-0914-raw`. Worktree `~/lfs-rebase-0914`.
- Version gates bumped 2.17.57 -> **2.17.58** (master tagged 2.17.58 on 09-03;
  a released 2.17.57 lacks the code): sanity 157c/157d, conf-sanity 300
  (two), 301-304, and their skip messages; 68094-18 reply updated to match.
  Patches 4, 6, 11 (context), 12, 13 differ by those lines only.
- Conflicts: master's LU-18586 (`d179522efa`) put `find_param` on the heap
  (`llapi_find_param_alloc()`); `lfs_find()` now allocates and frees it, and
  commits 10–17 had `&param`/`param.` rewritten per tree (10–14 had merged
  silently and would not have compiled). man3 list: alphabetical merge.
- Verified: range-diff shows only those changes (21–25, 27, 28 identical —
  the osd/uapi auto-merges applied as-is); userspace sweep 29/29 build=0;
  checkpatch identical per commit (118/118); messages identical bar one
  trailing blank line on the five hand-resolved commits; no test-number
  collisions. **Not run:** kernel module build (no modules-enabled tree
  locally), VM sanity/conf-sanity, lreview (held: tokens).
- 68582 and 64945 not rebased or checked for the same timeout.
- **Plan changed after Andreas (09-14):** do NOT push the whole rebased
  series. 68616/68617 stay as they are so they can land; 68231 is already
  on master (PS8, rebased on Gerrit, +1 kept). Push only 68094, 68095, 68156,
  68157 on top of 68231 PS8, after lreview on each. Branch `lower-on-68231`:
  all 9 lower commits apply, patches identical (range-diff), build 9/9;
  lustreapi.7 lint +3 false warnings without 68616 (same class as master's).
- **lreview 68616/68617 (09-14): no code bugs, 4 low findings, all
  verified; hold for a refresh, do not push for them.** 68616: message
  lines 47-54 describe an earlier PS (the parent checker already reports
  prose after .PP). 68617: AVAILABILITY "release 0.10.0 / commit 0.9.1" -
  no 0.10.0 tag exists (0.9.1 then 1.0.0), but lfs.1, lfs-find.1 and
  lfs-getstripe.1 on master use the same pair; message lines 3-6 overstate
  "hidden" (old checker already listed the findings, among 39 others).
- **lreview 68094/68095/68156/68157 (09-14), 11 findings, verified:**
  mode 755->644 on sanity.sh (68094) and conf-sanity.sh (68156) - OURS
  from the gate bump, FIXED. 68095 (medium): plain `--projid` with type
  from d_type never gathers (find_want lacks fp_check_projid), so
  get_projid() gets a stale stx_mode; the stale mode is pre-existing on
  master, but 56El's new `--projid 0` checks rely on it and may fail on a
  >= 6.0 client (tmpfs answers FSGETXATTR); VM kernel 5.14 cannot show it.
  Also 68095: 56El's `-type f` count check likely passes without the
  patch; find_prefilter/find_want could take const param. 68094: message
  lines 31-33 contradict line 83 (lmd_fid clear location); comments name
  LLAPI_SCAN_INO and llapi_scan_fid() that come later. 68156: plugin path
  uses getenv("LUSTRE") - secure_getenv like liblustreapi_project.c;
  llapi_scan_device.3 "called for every object" - skipped inodes never
  reach lfsp_filter. 68157: message's "only edits" omits DEFAULT_PROJID.
  NOT fixed yet except the mode.
- **Fixes, 09-14, branch `fix-first4`** (worktree `~/lfs-fix-0914`, on
  68231 PS8, nothing pushed): 68094 message + two comments, 68156
  secure_getenv + man wording, 68157 message. **68095 left as is:** the
  stale-mode fix was built and A/B-tested on the VM (lfst, tmpfs under
  Lustre, l1 -> a Lustre file, arms A/B/A/B via LD_PRELOAD): unfixed and
  fixed gave the SAME correct answers, so lreview's failure scenario does
  not happen there; fix and test change reverted (kept at tag
  `backup/fix-first4-with-projid-0914`). Reply to that finding with the
  A/B, do not claim a fix. The 56El `-type f` and const findings: not done.

## Earlier (2026-09-13): round 3 fixed, not pushed

The overnight AI reviews of 09-11/12 and adilger's two 68094 comments: 42
threads, each verified against the carried stack. **40 fixed, 1 already
fixed (68288 44cf4ff2), 1 moot (68160 bd2794d9, lfind.c is gone), 1
declined** (68417 7d9d284f: linkno 1 would skip a name when link 0 is
unlinked mid-run).

- Tips: `lu-upper-onto-lfs` = `r3-0913` = **a324654503** (all 26 commits),
  `lu-20637-names-onto-lfs` = `fold-r2` = **30c83d610b**. Backups
  `backup/{upper,lower}-pre-r3-0913`. 68582 and 64945 unchanged.
- Behavioural fixes, each proven against the unfixed build: `--since-cookie`
  temporaries private to the run (overlapping runs lost the rewrite), a
  failed stdout holds the cookie (sanity 160ac `/dev/full` fails on the old
  library), `--since 18:00` seconds, a failed MDT count is an error (exit
  0 -> 5), changelog `sc_got` names the lazy bits, ZFS stops declaring
  NODUMP, `LMV_SHARD` = 1<<47, 157c/157d gate on `CLIENT_VERSION` and put
  157c on a random MDT.
- Verified: build sweep 26/26 clean, checkpatch identical per commit,
  trailers identical; VM sanity 157c 157d 160aa-ad and conf-sanity 300-304
  PASS, fixture untouched. **Not run:** the two ZFS changes (compile only),
  157c under DNE.
- Replies for all 42 are drafted (`docs/rounds/r3-0913/replies-r3/`); they
  go out after the push, on the patchset each comment was written on.
- Noted, not chased: every commit message in the series has lost its
  backslashes (Gerrit too); Janitor calls sanity2 test_160g new on
  68813/68818.

**Open:** run lreview on each of the 26 commits (one at a time), then push when the user says so; the 09-11 list below still stands. Paused 09-13 by the user.

## Tomorrow: start here (end of 2026-09-11)

**Nothing is running.** The clone VM (`rhel9.7-server-mgs-mds-clone`) is up
with no Lustre mounted, no modules loaded and no loop devices; the fixture
(`/tmp/lustre-mdt1`, `/tmp/lustre-ost1`, `/tmp/lustre-ost2`) md5-checked
unchanged after every run. Waiting on more AI reviews — the user's call at the
end of the day.

**Everything from today is local and unpushed.** Two stacks, both carried and
verified:

- `lr-68160` `lu-20637-names-onto-lfs` = **1c4ec75ae5**, 9 commits: 68094,
  68095, 68156, 68157, 68158, 68159, 68160, 68163, 68288. **lfind(8) is gone**
  — 68160 is `lfs find --device DEVICE`, a bare block device, and `--fsname`
  (lsnapshot's validation). See [[lfu-lfind-into-lfs-find]].
- `lr-upper` `lu-upper-onto-lfs` = **36363eb242**, 17 commits: 68415–68420,
  68726, 68727, 68810–68818.
- `lr-68582` = **4f436091df** (LU-20546) and `lr-64945` = **828d176103**
  (LU-20050): their own AI findings, code and message.
- Backup tags before each rewrite: `backup/{lower,upper}-pre-fold-0911` and
  `backup/{lower,upper}-pre-r2-0911`.
- All 26 commits build clean, checkpatch findings identical to the originals,
  find-device harness 30/30. On the VM: conf-sanity 300–304 PASS,
  `llapi_scan_test` 4/6/11/12/14/15/16 PASS, sanity 56El PASS — and 56El FAILS
  with the `!no_projid` guard removed, which is what says the new coverage
  works.

**Open, in the order they matter:**

1. **Push the round when the user says so.** Every reply posted today says
   "Done in the next PS", so the push is what makes them true: the nine lower
   changes, the seventeen upper ones, then 68582 and 64945 separately. 68094
   and 68095 are in the carried set now and get new patchsets too.
2. **68818's two adilger threads, open on purpose** (the OSD series was
   skipped today): `CAP_DAC_READ_SEARCH` rather than `CAP_SYS_ADMIN` — the
   page matches the code, so `mdc_request.c`'s `capable()` check changes with
   it — and nodemap ID-offset filtering for multi-tenant scanning.
3. **Still open from 09-10**: the `llapi_scan()` front door (user still
   thinking; rule 6 stands, walk branch must carry find's thread count, a
   dirent-answered predicate is never worth offloading); filter pushdown into
   `lfu.ko`; `Documentation/man4/` pages plus Group A's style and split before
   the OSD series can land; untested DNE for the subtree map, filesets, hard
   links; the progress artifact's masthead counts (19 changes / 0 landed) not
   re-checked since 09-01.
4. `lustre-scanfid` `lu-20720-fold` `42eed1e556` still folds into 68818 when
   that series next moves.

**Traps today, all in memory:** VM test binaries carry `DT_RPATH` to
`~/lfs68160-inst`, so an A/B arm needs `LD_PRELOAD`, not `LD_LIBRARY_PATH`
([[lfu-vm-rpath-trap]]); the hand-built scan plugin needs `-lext2fs` or
`dlopen()` fails on `unix_io_manager` and every scan answers `-ENOTSUP`
([[lfu-scan-plugin-trap]]); an installed library is a libtool relink, so
compare `.text`, not md5; and a fixup whose text a later commit *moves*
conflicts twice, where `git log -S` shows nothing because a move keeps the
occurrence count.

## The AI-review round: six defects and 28 threads (2026-09-11)

Andreas' CR-1 on 68160 (22 comments) and his 68159 round were worked through
first; then a sweep of every open thread whose last word was not ours found 37,
of which six were real defects. All six are fixed, each proven against the
unfixed build, and folded into the commit that owns them
([[lfu-defect-queue-0911]], [[lfu-unaddressed-threads-0911]]).

| # | Change | Defect | unfixed → fixed |
|---|---|---|---|
| 1 | 68094 | `lfsp_size` tail read unbounded | SIGSEGV → `-EINVAL` (cap 4096) |
| 2 | 68094 | `LMV_FOREIGN` alone fetched no LMV | `lfsp_got` 0x2000000001 → promise kept |
| 3 | 68156 | OST `lfsp_got` promised MDT fields | 0x180800000000 → narrowed |
| 4 | 68156 | one worker's EIO left the others running | 63/63 chunks → 0/63 |
| 5 | 68726 | close guard one-sided | second close hangs → `-EBUSY` |
| 6 | 68582 | `ptlrpc_req_put()` LBUGs a pool request | code path + VM module build |

Nineteen more threads were fixed on the user's "fix, then reply" call: the
linkea walk is a byte cursor now (`scan_linkea_next()`, fuzz-compared against
the old index walk — 3M compares, 717k walk steps, 0 mismatches), `ss_emitted`
is counted before the callback as a walk counts it, both end-of-scan warnings
name their target, sanity 56El covers `--projid N` on an object with none, and
the rest are man-page and commit-message corrections. Two declined with a
reason: 68158's optind split (a b2_15 fix would target `lfs_find()`, which that
patch replaces — the user's call) and the batch `lfsp_got`/`lfsp_stats` getter.

**One correction worth keeping:** 68095's `Fixes:` tag. 6b8e97b76c47 stays —
the `--foreign` arm printing the previous object's attributes is its, and
`gather_all` entered the `cb_get_dirstripe()` condition there — with
c99a393125bc and 3dad616e09fc added for the older halves. Check which bug a tag
is for before proposing to replace it.

## The walk with threads: the 2.4× gap was the default (2026-09-10)

Follow-up to the subtree benchmark. Harness only — no library change. Data
`bench-data/2026-09-10/walk-threads-two-node.txt`, script
`tests/lab-sub/benchthreads.sh` + `inflight.sh`.

`lfs find` picks `min(4/MDT, CPUs/2)` **floored at 4** (`lfs.c`
`calculate_default_thread_count()`) — 4 on the 4-CPU client. Walk FID sets at
1, 4 and 8 threads: identical, zero duplicates. Cold, median of five:

| scope | stock | walk ×1 | **walk ×4** | walk ×8 | offload |
|---|---|---|---|---|---|
| `/` | 8.886 s | 21.456 s | **9.050 s** | 7.779 s | 0.295 s |
| `bench` | 9.023 s | 20.876 s | **8.779 s** | 7.681 s | 0.400 s |
| `bench/d3` | 2.531 s | 2.411 s | 2.489 s | 2.390 s | 0.409 s |
| `d0` | 0.035 s | 0.032 s | 0.033 s | 0.033 s | 0.403 s |

- **×4 matches stock** (1.02×, 0.97×; 3.32 vs 3.25 requests in flight). The
  gap was entirely the one-thread default.
- **Threads only help across directories.** `d3` (one dir, 10k files) runs
  ~0.95 in flight at every count; idle workers burn ~2.6 s CPU for nothing.
- **×8 hits this lab's MDT**: 6.26 in flight, 320 → 539 µs per request, 1.16×.
- **Offload ratios hold** against the fair walk: 30.7×, 21.9×, 6.1×; d0 still
  walked 11× faster. Crossover still ~2–5%.
- Consequence: `llapi_scan()`'s walk branch must carry find's thread count
  (design open question 6). **Untested:** DNE — find's formula reads
  `llapi_get_obd_count()`, which answers 64 on one MDT.

## `llapi_scan_mount()` scans a subtree — built, oracled, measured (2026-09-10)

`42eed1e556 LU-20730 llapi: llapi_scan_mount() scans a subtree` on
`lu-20720-fold` in `lustre-scanfid`, **unpushed**, on top of the nine on
Gerrit (it would fold into 68818). Design `design-llapi-scan.md` §5.1; data
`bench-data/2026-09-10/subtree-two-node.txt`; harness `tests/lab-sub/`.

The root asks for everything, as before. Any other directory runs the
directory-only pre-pass `--paths` already had, then filters on the parent's
membership, memoised per directory. Client-side: the MDT still streams
everything.

**Oracle, as FID sets:** diff 0 both ways on `bench` (87,894), `bench/d3`
(10,000) and `d0` (50). Root +2 = the two nameless objects, identified
(`[0x200000400:0x1:0x0]`, `[0xe:0x0:0x0]`, fid2path ENODATA). Run with three
different demand masks, same answers.

**Measured**, two nodes, one MDT, `-mtime -30 -type f`, cold, median of five:

| scope | share | stock `lfs find` | offload | |
|---|---|---|---|---|
| `/` | 100% | 8.955 s | 0.291 s | **30.8×** |
| `bench` | 99.9% | 8.919 s | 0.412 s | 21.6× |
| `bench/d3` | 11.4% | 2.510 s | 0.405 s | 6.2× |
| `d0` | 0.06% | 0.035 s | 0.404 s | **walk 11× faster** |

A subtree offload is **flat at ~0.405 s**, the root plus a +40% pre-pass,
whatever it returns — §5.1's O(filesystem) read + O(subtree) output, exactly.
Crossover ≈ **2–5% of the filesystem** (interpolated). **Rule 6 stands.**

**Three traps, each of which would have produced a wrong headline:**

- `lfsp_want = 0` makes the walk pay for layouts and xattrs: 21 s, a fake 73×.
- `-type f` alone is a **readdir** in stock `lfs find`: 0.172 s cold, no
  per-object request. `-mtime -1` matched only 4 files (fixture past 24 h),
  hence `-mtime -30`.
- The walk arm is 2.4× slower than stock at the root **because it runs
  serially**: `lfsp_thread_count` defaults to one thread, `lfs find` to
  min(4/MDT, CPUs/2), floored at 4. Glimpses and statahead both measured and ruled out first. → design
  open question 6: `llapi_scan()`'s walk branch must inherit find's
  parallelism.

**A predicted bug that did not reproduce**, tested against the unfixed
library: a caller not asking for `PARENT` still got it, because the stream
ships the link tail unconditionally. The guard (subtree forces
`PARENT|LINKEA`) stays for when pushdown lets the MDT drop the tail.

**Not tested:** DNE (one MDT, so the map's lock and memo race are
unexercised), a fileset mount, hard links (fixture has none). VMs shut down,
fixture intact.

## The OSD series folded for review, and `Test-Parameters: ignore` verified (2026-09-10)

**PUSHED 2026-09-10** as 9 new changes, with `Test-Parameters: ignore`
confirmed present on the uploaded commits:

| change | |
|---|---|
| [68810](https://review.whamcloud.com/c/fs/lustre-release/+/68810) | LU-20720 osd: attributes and a private otable iterator |
| [68811](https://review.whamcloud.com/c/fs/lustre-release/+/68811) | LU-20720 osd-ldiskfs: read the inode table ahead of the scan |
| [68812](https://review.whamcloud.com/c/fs/lustre-release/+/68812) | LU-20720 osd-ldiskfs: read the inode table, not the inodes |
| [68813](https://review.whamcloud.com/c/fs/lustre-release/+/68813) | LU-20720 osd: xattrs from the otable iterator |
| [68814](https://review.whamcloud.com/c/fs/lustre-release/+/68814) | LU-20720 lfu: an object stream from the OSD otable iterator |
| [68815](https://review.whamcloud.com/c/fs/lustre-release/+/68815) | LU-20722 llapi: a scan backend for a target in service |
| [68816](https://review.whamcloud.com/c/fs/lustre-release/+/68816) | LU-20730 lfu: the Object Stream over OBD_IDX_READ |
| [68817](https://review.whamcloud.com/c/fs/lustre-release/+/68817) | LU-20730 osd-zfs: the LFU record and an index walk |
| [68818](https://review.whamcloud.com/c/fs/lustre-release/+/68818) | LU-20730 llapi: llapi_scan_mount(), a scan from a client |

**Not monitored, deliberately.** These are for **Lustre 2.19**, not the
current cycle — do *not* add them to `gpoll`, and do not triage what lands on
them. `Test-Parameters: ignore` means Verified-1 on all nine by design, so
there is no CI signal to watch; the Janitor will review them anyway and its
comments can wait until the series is picked back up for 2.19.

Gerrit warned "subject >50 characters" on six of the nine. The commit-msg
hook's own limit is 62 and none exceed it, so this is Gerrit's stricter
advisory, not a blocker.

Branch `lu-20720-fold` in `lustre-scanfid`, **9 commits off `49206c2ffe`,
unpushed**. `lu-20720-orig` keeps the 12-commit shape it replaces.

### `Test-Parameters: ignore` is real, and it fails rather than skips

Andreas' advice checked before use. It is honoured, but not the way the name
suggests:

| check | result |
|---|---|
| landed git history | **0 uses** — and that proves nothing: `ignore` blocks landing by design, so it *cannot* appear in `git log`. Wrong instrument. |
| open changes on Gerrit | 25+ in active use, both `ignore` and `Ignore` |
| Maloo / Autotest | never run on a tagged patchset |
| jenkins | posts **Verified-1 "Build Failed"** — 25 of 25 open tagged changes |
| Gerrit Janitor | **still runs, every patchset** (240 comments on 65918) |

Change **60441** is the natural experiment: PS1 `Test-Parameters: trivial` →
Verified+1 with Maloo and Autotest; PS3 `Test-Parameters: ignore` →
Verified-1 with neither. Nothing else changed. The red Verified-1 *is* the
mechanism that blocks landing — it is not a build to debug. So `ignore` buys
no build and no test, **not** no review.

### The fold: 12 commits → 9, and no `wip` subjects

Four commits were titled `wip …` with the body "Port of the out-of-tree
patches, to be split and rewritten" — publishing those under our name on a
public review server was not worth it. Rewritten with real messages (trees
untouched). And the item-2/3a/3b commits folded into B1/C2 as the board has
said since 09-10, so a reviewer of B1 does not review a module-parameter
design that the next commit deletes.

| # | commit | |
|---|---|---|
| 1-4 | Group A | reworded only; attributes + private iterator, readahead, block parse, xattrs |
| 5 | B1 `lfu.ko` | absorbs the kernel half of items 2, 3a, 3b |
| 6 | C2 `libscan_kernel.c` | absorbs the userspace half of the same three |
| 7-9 | LU-20730 | trailer only |

The three folds split **cleanly by path** — kernel half is exactly
`lustre_lfu.h` + `lustre/lfu/`, userspace half exactly `lustre/utils/`, no
file unclassified.

### What was verified, and the one build that was actually needed

**Tree hashes did the work.** Comparing the two series commit by commit:
commits 1-4 and 7-9 have trees *byte-identical* to the originals, and C2's
tree equals the old item-3b tree — already built and lab-tested. Exactly
**one** tree in the new series never existed before: B1, which has the kernel
side folded in but not the userspace side, so `lfu_ring.c` must compile
without its consumer.

And B1 needed no VM either: every file it touches
(`lustre_lfu.h`, `lustre/Makefile`, `lustre/lfu/Makefile`, `lfu_ring.c`) is
byte-identical to item-3b's, and *every* difference between B1 and item-3b
lies under `lustre/utils/`, which cannot affect a module build. The local
tree is `--disable-modules --disable-server`, so this replaced the VM rather
than skipping the check.

- **Final tree hash** equals the original tip's, `dec3a8d4` — the fold moved
  changes between commits and lost none. (Then one deliberate fix on top.)
- **Userspace build at all 9 commits**: green.
- **Change-Ids**: all 9 preserved, so Gerrit keeps the identities.
- **checkpatch**: one real finding, fixed — `lustreapi.7`'s SEE ALSO had
  `llapi_scan_mount` before `llapi_scan_fid`. The rest is the known noise
  (MAINTAINERS) plus inherited style in the ported Group A code: trailing
  `*/` on its own line and a few 81-87 column lines. **Owed**, with the
  `Documentation/man4/` pages for the module parameters, when Group A is
  split properly for landing.

## Tomorrow: the RPC spike, and two owed items (2026-09-09, end of day)

Branch `lu-20720` in `lustre-scanfid`, **6 commits off the round-23 tip,
unpushed**. Lab torn down, VM off.

### 1. `lfs find` over the wire — the spike (LU-20721)

**Read the code before sizing it again: the transport is closer than the
design said.** `design-osd-port.md` §4 treated `OBD_IDX_READ` as "largely
exists"; what the code shows is that *the otable iterator already speaks the
index-walk language*:

- `dt_index_walk()` needs `init / load / next / key / key_size / rec / store`,
  and the otable iterator implements **every one** (`osd_scrub.c:3856-3859`).
  It was built as a `dt_index`; that is how LFSCK drives it.
- The record fits the existing container format unchanged. `II_FL_NOKEY` and
  `II_FL_VARREC` are already in the protocol, and the comment says *"we only
  support fixed-size key & record"* — which is our case exactly: `struct
  lfu_rec` is fixed at 168 bytes and `key_size()` returns `sizeof(__u64)`.
- `rp_attrs` already carries `ii_attrs` from the request through to `init()`,
  which is where our iterator flags would go.

**So the server side is two soft things, not an architecture:**

| | |
|---|---|
| the FID whitelist | `dt_index_read()` takes quota, layout-rbtree and normal FIDs; the otable is a *local* FID and is refused at the door |
| `dt_otable_features` | declared with no initialiser (`dt_object.c:721`), so `dif_recsize_*` are zero. Needs real sizes and a `dt_index_feat_select()` branch |

`osd_otable_it_key()` returns NULL, so a request must set `II_FL_NOKEY` —
which is what that flag is for.

**The client side is the genuinely new part**: MDC has no `OBD_IDX_READ`
sender at all, only OSP does (`osp_object.c:1846`). Plus the ioctl, the bulk
receive and the `lfs find` hook.

**Do it on the three-node lab** (MGS/MDS `.10`, OSS `.20`, client `.101`). A
loopback client cannot show the thing being measured: today's 4.7 s of system
time was 88k ioctls, which over a wire is 88k round trips against a few
hundred RPCs for the offload. Single-node makes both arms pay nothing for it.

### 2. Per-open target selection

`lfu.ko` takes its target as a module parameter, so one load serves one
target. It bit on the first run: `lfind --local` found three targets and
scanned the MDT **three times** (441 = 3 x 147). This blocks any honest
`--local` and is the smaller of the two owed items.

### 3. Xattrs across the ring (B3)

The core classifies from `trusted.lma` and names from `trusted.link`, both
through `so_xattr`. B1 synthesises the LMA from the FID and flag bits and
carries nothing else, so the kernel path answers no names, layouts or SOM
sizes yet. `rec(DORA_XATTR)` exists in group A and is unused by the module —
this is wiring, not new design.

**Order:** 2 and 3 are prerequisites for a useful `lfind`; 1 is independent of
both and is where the interesting number is.

## Split out: `llapi_scan_mount()` wants a ticket of its own (2026-09-10)

Filed as **LU-20730** on 2026-09-10; draft in
[`docs/tickets/llapi-scan-mount.md`](tickets/llapi-scan-mount.md). Three
commits carry it:

```
bc0fa6f5e4  LU-20730 lfu: the Object Stream over OBD_IDX_READ
bc5092d4d5  LU-20730 osd-zfs: the LFU record and an index walk
e36dd5a14a  LU-20730 llapi: llapi_scan_mount(), a scan from a client
```

They passed through an `LU-00000` placeholder first, because the commit-msg
hook only pattern-matches `LU-\d+` and never checks the ticket exists — a
guessed number would have attached them to somebody else's ticket silently.

**Why.** LU-20721 is scoped as "`lfs find` offloaded to the servers" and had
grown a public API that has nothing to do with `lfs find`. Same split and same
reason as LU-20722: an API deliverable is not a tool deliverable, and
`docs/tickets/` already carries `llapi-scan-api.md` and
`llapi-scan-device.md` beside the tool tickets. The four now read:

| | |
|---|---|
| LU-20720 | the engine — kernel OSD scanner and its ring |
| LU-20722 | `llapi_scan_device()`'s kernel backend — server-local API |
| **LU-20730** | **`llapi_scan_mount()` — client API and its transport** |
| LU-20721 | `lfs find` offloaded — the tool, now with **zero commits**, which is honest; depends on LU-20730 |

Transport and API stay in **one** ticket: the transport has no consumer
without the API and the API cannot exist without it.

**Done now because nothing is pushed.** Re-tagging cost three
`git commit --amend`s today; after a push it would have cost a re-spin of
three Gerrit changes and a review history that reads oddly. Verified the
re-tag changed messages only — tree identical to `9f83713e58`, Change-Ids
preserved, still 12 unpushed, no duplicates.

**Left in LU-20720 deliberately:** `DORA_LFU` and `DOIF_INDEX`. They are
iterator capabilities anything driving the otable could use, even though this
is what they were built for. Said so in the draft so a reviewer is not
surprised.

## `llapi_scan_mount()`: the client entry point (2026-09-10)

`9f83713e58 LU-20721 llapi: llapi_scan_mount(), a scan from a client`, on
`lu-20720`, **12 commits unpushed**. The 30x had been real and unreachable —
there was no way to it but a raw ioctl. Now there is an API.

### Shape

**A fourth backend, not a fourth thing that resembles one.** The unit of work
is an MDT rather than a slice of a target, so `tt_chunks` is the MDT count and
a chunk index selects one — and the scan core already shards chunks across
workers, so **N MDTs scan in parallel with nothing added for it**. Only the
record knows which MDT answered, since one `llapi_scan_tgt` now covers many,
so `llapi_scan_obj` gains `so_mdt_index` and the core prefers it to the
target's when set.

**One record→object translation.** `libscan_kernel.c` had it and the client
needs the same one; with plugins the kernel backend is dlopen'ed and cannot
call back into liblustreapi, so it was one inline in a header or two copies
that drift. `lustreapi_lfu_rec.h` now holds it and both backends use it.

### The bug, and what it exposed

First run: every record delivered, then **`-ENODEV`**. `llapi_get_obd_count()`
answers the **size of the descriptor array** — 64 on a filesystem with one
MDT — so chunks 1..63 asked for targets that do not exist.

`lmv.*.target_obd` lists the indices themselves, and that fixes a second thing
a count could never express: **MDT indices need not be contiguous.** MDT0000
and MDT0003 with nothing between is a real configuration. A target that is not
`ACTIVE` is now refused at open rather than scanned around — a scan that
skipped one would return a short answer that reads exactly like a complete
one.

### Verified

| set | `llapi_scan_mount()` | the ring | diff |
|---|---|---|---|
| visible | 87,961 | 87,961 | **0** |
| `--internal` | 88,051 | 88,051 | **0** |

And **from a client that is not the server: 87,961 = 87,961, diff 0**, with
**87,957 of those records carrying a name and parent FID** rebuilt from the
linkea that crossed the ring and then the wire. That is the whole chain —
OSD iterator → `trusted.link` → record tail → `OBD_IDX_READ` bulk → client →
`lfsr_name`.

Man page written (`llapi_scan_mount.3`, groff-clean), indexed in
`lustreapi.7`. checkpatch: 0 errors, only the new-file MAINTAINERS note.

### What it deliberately is not

It scans the **whole filesystem whatever directory names it** — a target has
no subtree. The manual page says so plainly. Choosing between this and
`llapi_scan_namespace()` on that basis is `design-llapi-scan.md`'s job, and
the next piece of work.

## osd-zfs joins the RPC path, and the resume test that was missing (2026-09-10)

`474b9cad4d LU-20721 osd-zfs: the LFU record and an index walk`, on
`lu-20720`, **11 commits unpushed**. This was the "first thing a user tries
must not be a coin flip on backend" item, and it is now closed.

`rec_size()` and `rec(DORA_LFU)` are the ldiskfs ones — the record comes from
`dt_otable_lfu_rec()`, which needs only `rec(DORA_ATTR)`/`rec(DORA_XATTR)`,
and osd-zfs already serves both. ZFS keys its xattrs by the full `trusted.*`
name in the SA nvlist and in the xattr directory, which is exactly the name
the builder passes, so **nothing about the record differs between backends**.

**`DOIF_INDEX` needs one more step on ZFS.** `dmu_object_next()` answers
strictly after `ooi_pos` — which is already why a private iterator starts *at*
the hash rather than after it — so an index walk, which must return the record
*at* the hash, starts one further back again: `ooi_pos = hash - 1`, clamped at
0 because object 0 is the DMU meta-dnode and never a target object.

### The test that mattered was the one that nearly did not happen

The first ZFS run looked perfect: 2,100 records, **diff 0** against the ring.
It also used **one RPC** — the whole stream fit a single 1 MiB bulk, so it
exercised **no page boundary at all**, which is the only place the resume
arithmetic lives. Shrinking the buffer is what actually tests it:

| buflen | RPCs | records | vs the ring |
|---|---|---|---|
| 1 MiB | 1 | 2,100 | diff 0 |
| 64 KiB | 8 | 2,100 | diff 0 |
| 32 KiB | 15 | 2,100 | diff 0 |
| 16 KiB | 29 | 2,100 | diff 0 |
| 8 KiB | **58** | 2,100 | **diff 0** |

**A green oracle over one RPC says nothing about a resume.** The ldiskfs
off-by-ones were found only because 88k objects happened to need 20 RPCs.

So the same sweep went back over ldiskfs, which had only ever run at 20:
**2,446 calls, 2,445 resumes, 88,051 = 88,051, diff 0.**

### Lab notes

- ZFS lab built with `TMP=/tmp/zfslab FSTYPE=zfs llmount.sh`, which keeps its
  vdevs in `$TMP` — so the ldiskfs 88k fixture in `/tmp/lustre-*` survived
  untouched and `NOFORMAT=1 llmount.sh` brought it straight back.
- `$TMP` must exist first; `llmount.sh` does not create it.
- **A ZFS scan of a live target does not see what has not synced.** Right
  after creating 2,000 files the scan saw 40 objects; after a txg sync, 2,010
  against the client walk's 2,006. Not a bug — a target scan is an on-disk
  view, which is the staleness `design-llapi-scan.md` §4 says a caller must be
  able to ask about.
- Cost me a wrong turn: I read `/tmp/zfsmount.log` and diagnosed a stale
  `lustre-r18` module path, from a **root-owned log dated Sept 3**. Same trap
  as §"round 18 log": assert the timestamp before believing a log.

## Design: `llapi_scan()`, one door (2026-09-10)

[`docs/design-llapi-scan.md`](design-llapi-scan.md), v0.1, for LU-20721.
The user's question: if the offload is faster, nobody will use
`llapi_scan_namespace()`, so should a front door pick between them?

**Yes — with the premise corrected, and the correction is the design.**
"Faster" is not a property of the source but of *(source, query)*: a target
scan is whole-target by construction, so offloading `find
/mnt/lustre/home/alice/tmp` on a billion-object filesystem is not 30x, it is
a catastrophic loss. So the front door picks **the cheapest source that can
answer this question**, not the fast one — which is the rule
`design-lfs-find-offload.md` §2.1 already reached for `lfs find`, moved one
layer down so every consumer inherits it instead of reinventing it.

**Answer-equivalence is a prerequisite, not a detail.** The two sources
return 87,944 and 87,958 — within 0.02%, which is exactly how a silent swap
becomes a plausible wrong answer. The offload must apply the classifier
(87,946) and reconstruct paths; **this morning's raw-linkea work is what makes
that possible at all**, and before it the two sources could never have
answered the same question. What remains unequal — staleness, ordering,
privilege — is asked about rather than hidden.

Shape: `llapi_scan(path, sp, cb, data)`, the same signature as
`llapi_scan_namespace()` so it is a drop-in; `lfsp_source` appended to pin a
source; `ss_source` in the stats to report which ran, without which a test
cannot pin what it is testing. The three doors all stay — the oracle needs
both sources, and the HLD's model is pluggable Input Scanners with a
selector, not one absorbing the others.

Phase 1 is root + admin + ldiskfs, which is `lfs find /mnt/lustre -mtime -1`,
the case measured at 30x. **osd-zfs `DORA_LFU`/`DOIF_INDEX` comes first**, or
the first thing anyone tries is a coin flip on backend.

Open, and unchanged: duplicates across merged MDT streams — for Andreas. v1
sidesteps it by delivering per MDT with `lfsr_mdt_index` set, so a duplicate
is visible rather than silently merged.

## The number: 30x stock lfs find, 4401x fewer round trips (2026-09-10)

Two nodes, so the round trips are real. Server `.10` (MGS + `lustre-MDT0000`
+ 2 OSTs), client `.101`, the 2026-09-09 fixture of 88k files, predicate
`-mtime -1 -type f`, five alternating pairs, **caches dropped on both nodes
before every run**. Raw: `bench-data/2026-09-10/rpc-two-node.txt`; harness and
script in `tests/lab-rpc/`.

| arm | count | median wall | range | user + sys | **RPCs to MDT0** |
|---|---|---|---|---|---|
| stock `lfs find` | 87,944 | **8.770 s** | 8.641–9.030 (±2.2%) | 1.2 + **9.7** | **88,028** |
| offloaded stream | 87,958 | **0.292 s** | 0.285–0.312 (±4.6%) | 0.00 + **0.01** | **20** |

**30.0× on the median, and 4,401× fewer round trips.** The noise floor is two
orders of magnitude below the gap. Stock burns 10.9 s of CPU inside an 8.8 s
wall — more than a core, all of it RPC processing; the offload spends 0.01 s.

**Yesterday's 21× understated the walk, exactly as the board predicted.** On
one node the same fixture gave stock 5.394 s; over a wire it is 8.770 s. The
3.4 s difference is 88k round trips that cost nothing on loopback.

### The counts, and why they differ

```
87944  stock lfs find     namespace-visible, a walk
87946  lfind --target     + 2 nameless MDT objects a walk cannot reach
87958  lfind --internal   + 12 internal objects (no LMA / NOT_IN_OI)
87958  offload harness    identical to lfind --internal
```

That last line is the point of the harness: it spells its predicate out, and
**its answer is checked against `lfind`'s real predicate code over the same
object set.** A finished `lfs find` would apply the classifier and land on
87,946.

### Our own `lfs find` does not regress the walk

Third arm, same run, alternating: the series' `lfs` (the LU-20605/LU-20611
rewrite of find onto the scan record) against upstream's.

| arm | count | median | range | RPCs |
|---|---|---|---|---|
| stock `lfs find` | 87,944 | 9.107 s | 8.861–9.339 (±2.6%) | 88,028 |
| **ours** | 87,944 | **9.037 s** | 8.806–9.719 (±5.0%) | 88,027 |
| offloaded | 87,958 | 0.292 s | 0.282–0.296 (±2.4%) | 20 |

**0.8% apart, and ours' range contains stock's entire range** — no
measurable difference. Same answer, same round trips, same 11.3 s of CPU.
The rewrite carries no cost on the namespace walk, which is the thing to be
able to say when it lands.

**Not 68160 exactly.** `lfs.c` and `liblustreapi_pfind.c` differ between
68160 and the tip — #11–#20 touch the find path too — so this is the tip.
Since the tip is indistinguishable from stock, nothing in between regressed
it either, which is the question 68160 would have been asked.

**Quote ~30×, not 30.0×.** Between-session drift moved stock's median from
8.770 to 9.107 (4%) on the same setup, larger than the within-run spread.

### What the number does not say

- **The harness is a spike consumer, not `lfs find`.** The client-side
  `llapi` integration is the remaining LU-20721 work — see below.
- **One MDT.** Several would parallelise the offload and not the walk.
- **Two VMs on one host**: virbr1, not a NIC. A real network widens this,
  since only the stock arm pays per round trip.
- `.20` was started and then shut down: `-mtime -1 -type f` never reaches an
  OST, so the OSS adds nothing and reformatting for a three-node filesystem
  would have destroyed the fixture. Two nodes is what "client != server"
  needed.

### Setting it up again

The client needs **this tree's whole module closure**, not just the changed
ones: `obdclass` changed, so `ptlrpc`, `mdc`, `lmv`, `lov`, `osc`, `fid`,
`fld`, `mgc`, `lustre`, `libcfs`, `lnet`, `ksocklnd` all have to come from
the same build or the symbol versions do not line up. Tar them off `.10`,
`depmod -a`, and check `modinfo -F srcversion` matches on both ends —
`tests/lab-rpc/` has the recipe. `.101` already had a pre-LFU
`~/lustre-release` build, which is the stock arm.

### Remaining for LU-20721

1. **The client consumer in liblustreapi**, so `lfs find` itself runs on the
   offloaded stream. The core is built around one target with one label and
   one MDT index (`scan_dev`, `tt_label`, `tt_index`), and a mount is many
   MDTs — so this is a public entry point of its own (one `scan_dev` per MDT,
   looping indices), not a fourth backend under `llapi_scan_device()`, which
   is what [[lfu-2.19-tickets]] already says the scope is.
2. osd-zfs: `rec_size()` + `DORA_LFU` + `DOIF_INDEX`.
3. A defined byte order on the wire — the format decision's business.
4. Per-user filtering; `CAP_SYS_ADMIN` only today.

## The RPC spike: the stream crosses OBD_IDX_READ, oracle diff 0 (2026-09-10)

`f044b65428 LU-20721 lfu: the Object Stream over OBD_IDX_READ`, on
`lu-20720`, **10 commits unpushed**. Functionally complete on one node; the
*number* still needs a client that is not the server.

### What was built

- **One record builder, in obdclass.** `dt_otable_lfu_rec()` builds
  `lfu_rec` + tail from `rec(DORA_ATTR)`/`rec(DORA_XATTR)`, which any otable
  iterator serves. The ldiskfs iterator answers `rec(DORA_LFU)` and a new
  `rec_size()` with it — built once per object and kept, since the page
  builder asks size before bytes — and `lfu.ko` calls the same function for
  its ring. Ring output verified byte-identical after the move (`--paths`
  diff 0, same 351,896 inline reads). `lfu.ko` dropped its own tier counting.
- **obdclass:** the otable FID past the `dt_index_read()` whitelist,
  `dt_otable_features` initialised (`DT_IND_VARREC`, 176..176+4096), no dt
  lock/version on an object that is an iterator.
- **Client:** `LL_IOC_LFU_SCAN` — llite → `ll_md_exp`, lmv → the MDT named
  in it, mdc sends `OBD_IDX_READ` with `NOHASH|NOKEY|VARREC` and a 1 MiB bulk
  of the caller's pages, copied from `osp_it_fetch()`. Containers handed to
  the caller whole. **It had to move to the `'f'` ioctl space**: lmv turns any
  other type away at the door (`ENOTTY`, and its `OBD_IOC_ERROR` says
  "unknown", not "unrecognized", which is why my dmesg grep missed it).

### The bug only the oracle could see, again

First oracle: **39 of 88,051 missing, in adjacent pairs, 20 RPCs** — two per
resume. Two off-by-ones stacked:

1. the page builder records the hash of the record it had *no room for*, so
   the client resumes there — but `osd_otable_it_load()` is LFSCK's
   checkpoint and starts *after* the hash. Skip one.
2. `dt_index_walk()` reads `load()` returning 0 as "positioned before, call
   `next()`" (IAM's contract); the otable's 0 means "on it". Skip another.

`load()`'s return couldn't change — LFSCK reads `> 0` as "table over". So
**`DOIF_INDEX`**: a second mode, position *at* the hash and answer as an index
does. LFSCK never sets it; the sender always does. Then a residual diff of 6:
all `[0x1:…]`/`[0x200000003:…]` local llog objects, because the ring snapshot
predated a remount. Same-mount snapshots: **88,051 = 88,051, diff 0.**

### The loopback number, for what it's worth

20 RPCs, 4,891 pages, 19.7 MB bulk, **4,400 records per round trip**.
0.110 s vs the ring's 0.102 s — 8 ms for the RPCs over loopback. Stock `lfs
find` on this fixture: 5.394 s and 88k round trips. **A round trip that costs
nothing measures nothing**; this number says the machinery works, not what
it's worth.

### What the number needs

1. **A userspace consumer** — a fourth `llapi_scan_device()` backend over
   `LL_IOC_LFU_SCAN` (mount + MDT index), reusing `libscan_kernel`'s
   record→object code over `lu_idxpage` containers, so `lfind --mount`/`lfs
   find` can run predicates and `--paths` on it.
2. **The three-node lab**: OSS `.20` and client `.101` up, the client
   carrying this tree's `mdc`/`lmv`/`lustre` modules. Then stock `lfs find`
   vs the offloaded scan, from `.101`, alternating, caches dropped — the
   measurement yesterday's 21× understated.

### Also owed

- osd-zfs: `rec_size()` + `DORA_LFU` + `DOIF_INDEX` (ldiskfs only today).
- The record on the wire is host-order; a defined byte order is the format
  decision's business, not this spike's.
- Consumers with `CAP_SYS_ADMIN` only; the HLD's per-user filtering is the
  server bulk filter's job, later.

## Item 3b done: names across the ring; the ring is bytes now (2026-09-10)

`5ce166a57f LU-20720 lfu: trusted.link across the ring, in a tail`, on
`lu-20720`, **9 commits unpushed**. Your call was raw linkea; this is it.

### The shape

`struct lfu_rec` is a **header** now — 176 bytes, `lr_reclen`/`lr_linklen`
appended — and the tail is the raw `trusted.link`, up to `LFU_LINK_MAX`
(4 KB). The ring is **bytes**, not records; a record may straddle the wrap
inside the kernel and is copied out in two parts, but `read()` returns whole
records only, each 8-aligned, so the consumer casts in place and walks with
`lfu_rec_next()`. No padding, no skip records: the ring isn't mapped, so
contiguity inside it would buy nothing. Wire version **3** — a v2 reader would
read tails as headers, and now refuses: *"speaks wire version 2 with 168-byte
records, this library expects 3 and 176"*, verified.

Linkea over the bound → `LFU_REC_LINK_BIG`, present-not-carried, `fid2path`'s
to answer; `ls_link_big` counts them. This is what lets `read()` promise
whole records into a buffer of known size.

### The bug the oracle caught

First run: `--paths` printed **nothing**, no error. `statt2` showed the links
*were* arriving (87,957 of 88,051 records). Cause: `--paths` makes **two
passes on one open** — the directory-map pre-pass, then the search
(`scan_device_run_prepass`, one `sb_open()`) — and the ring is one
enumeration per open, so the second pass read EOF at once. The device
backends re-read the disk for the second pass; the kernel backend now
reopens and rebinds when a chunk is asked for after the stream drained.
**Silent, plausible, and only an oracle finds it.**

### The numbers

| | kernel | device oracle |
|---|---|---|
| `--paths` | 87,957 | 87,957, **diff 0** |
| `-name 'f12*'` | 1,000 | 1,000 |
| MDT / OST counts | 87,961 / 44,005 | unchanged |

87,957 records carry a link, **46 bytes average**, max record 232, none over
the bound; 351,896 xattr reads, still **all inline**; zero stalls on the
16 MiB ring. `find /mnt/lustre` says 87,955 — the same 2-object difference
the device scan shows, so not the kernel path's.

**Cost:** raw reader, three alternating pairs, 3a vs 3b: **0.083 → 0.101 s**
warm. +18 ms for 88k link reads plus their tails, ≈200 ns/object. Cumulative
from item 2: 0.047 → 0.101 s, and the answer went from FIDs-only to
FIDs + real LMA + SOM + presence + names.

### Owed

`Documentation/man4/` pages for `ring_size`, `batch`, `private` — the tree
has 61 such pages, one per module parameter, and checkpatch asks. B1 never
had them; the rename surfaced it. Before push, once the parameters settle.

### Still not crossing: layout bytes

Deferred to filter pushdown on purpose — `-O`/`--pool` belong in the kernel
next to the bytes, and ioctl 2 has been reserved for that since B1. Shipping
up to 48 KB/object up a ring for userspace to test `-O` is the wrong direction.

## Item 3a done: LMA and SOM across the ring; layouts as presence (2026-09-10)

`a674c4fe61 LU-20720 lfu: trusted.lma and trusted.som across the ring`, on
`lu-20720`, **8 commits unpushed**. Measured, not projected, and oracle-checked
both ways.

### What crosses now, and how

The producer reads `trusted.lma` for every object, `trusted.lov` and
`trusted.som` for a regular file, `trusted.lmv` for a directory — all through
`DORA_XATTR` while the iterator still holds the inode-table block. LMA and
SOM cross **whole** (24 bytes each; the record already had the fields). LOV
and LMV cross as **presence**: `struct llapi_scan_obj` gains `so_xa_present`,
distinct from `so_xa_valid`, and `scan_size()` asks it. A backend with the
bytes sets both; the kernel backend can say "striped" without handing the
scanner a layout it would pass to `lfs find -O` as real. `-ERANGE` from the
OSD gives no partial copy, so a header-only read was never on the table —
presence and size are what a too-small buffer can learn, and that is enough
for the size question.

The 0x01 bit `lr_lfu` had free is `HAVE_LMA`; three reserved STATS slots
become the OSD's xattr tier counters. Wire version stays 2: no field moved or
changed meaning.

### The numbers

| | before | after | device oracle |
|---|---|---|---|
| `lustre-OST0000` | **1** | **44,005** | 44,005, **diff 0** |
| `lustre-MDT0000` | 87,961 | 87,961 | 87,961, **diff 0** |
| MDT `-size +0c / +1k / 0c` | — | 51 / 1 / 87,895 | same, all three |

**Every one of the 263,939 xattr reads on the MDT was inline** — external 0,
iget 0. Three reads per file, no I/O. The tier-1 model holds completely on
an mkfs.lustre-formatted MDT.

**Cost, alternating A/B, arms proven distinct by `srcversion`:** warm 88k
scan 0.047 s → 0.083 s, ten runs each, three pairs (.0470/.0470/.0475 vs
.0823/.0850/.0831). +36 ms for 264k reads = **136 ns per inline read**;
against yesterday's 0.254 s cold scan, about +14%; against stock `lfs find`
at 5.4 s, ~19× instead of 21×. Buys correct OST answers and correct sizes.
If it ever matters: three name-searches of the in-inode area per file could
be one pass.

### What 3a does not do — 3b

Names (`trusted.link`) and layout **bytes**. Both are variable-length and
`struct lfu_rec` is a flat 168-byte struct; that is the wire-format decision
(`lfu-wire-format`: deferred 2026-08-19, no owner, HLD asks for an
extensible format). Not to be invented in an afternoon.

### Lab notes

- `make install` fails on `/sbin/mount.lustre: Device or resource busy` while
  the fs is mounted, and aborts before the plugins; use
  `make install-libLTLIBRARIES install-sbinPROGRAMS install-exec-hook`.
- The oracle costs a stop/start of the target (~10 s); the client blocks and
  resumes. `umount /mnt/lustre` first for the MDT.

VM left **up and mounted**.

## Item 2 done: the target is bound per open (2026-09-10)

`88280b26fd LU-20720 lfu: bind the target per open`, on `lu-20720`, now
**7 commits unpushed**. Separate commit for now; fold into B1/C2 at push time.

`LFU_IOC_TARGET` (`_IOW 0xF4/4`, `struct lfu_target { char lt_name[64]; }`)
binds a descriptor to one target before its first `read()`. The name is the
target as mounted, `fsname-MDT0000`; the module appends `-osd`
(`lsi_osd_obdname`, `lustre_disk.h:128`) — its convention to know, not the
caller's. The `dev` module parameter is gone. Semantics, all exercised:

| | |
|---|---|
| read before bind | `-ENXIO` |
| bind a name no mounted target has | `-ENODEV` |
| empty / unterminated name | `-EINVAL` |
| `INFO` before bind | `PRIVATE` only, no OSD bit; after: `0x3` |
| rebind before the first read | allowed |
| bind after the scan started | `-EBUSY` |
| **old module, new library** | `ENOTTY` reported as `-EPROTO`, *"predates this library"* — refused, not silently scanned |

Built against `~/lfu-zfs` on the VM — the tree whose `Module.symvers`
produced the installed OSD modules — so only `lfu_ring.o` rebuilt. Utils
had to be **installed**, not run from the build tree: liblustreapi dlopens
`/usr/lib64/lustre/scan_osd_kernel.so`, and the installed one predates the
ioctl (the [[lfu-scan-plugin-trap]] again).

**Yesterday's fixture survived the reboot** — `/tmp/lustre-{mdt1,ost1,ost2}`,
88,230 MDT inodes. `NOFORMAT=1 llmount.sh` mounts it without reformatting;
plain `llmount.sh` would have destroyed it (`formatall` unless `NOFORMAT`).

### The result, and a finding underneath it

```
lustre-MDT0000   87961      (87,944 yesterday; a few files newer)
lustre-OST0000       1
lustre-OST0001       1
```

Three targets, three answers — before, three copies of the first. **But the
OST answer is wrong for a caller.** `--internal` on the same OST returns
**44,031** (≈ `lfs df -i`'s 44,275), so the iterator scanned it; the default
view shows 1 because `lfu_fill_rec()` synthesises the LMA with **no compat
bits**, so `LMAC_FID_ON_OST` is never set and the classifier holds every data
object back. The board had item 3 as "no names, layouts or SOM"; it is also
**"an OST answers 1 where the device scan answers 44k"**. That makes
`trusted.lma` across the ring the first item-3a deliverable, and it is
measurable: 1 → 44,031.

VM left **up and mounted** for item 3a.

## Round 24 PUSHED: 15 changes (2026-09-10)

Pushed `49206c2ffe` (#20 of 26) to `refs/for/master`, so the six `lu-20720`
commits stay local as intended. All 15 took a new patchset and **no new
change was created** — the highest change number is still 68727.

| change | PS | |
|---|---|---|
| 68156 | 19 | `lfsp_stats` moved to the end |
| 68157–68159 | 19 | carried |
| 68160 | 20 | carried |
| 68163 | 19 | the fix: backend into the programs, `lfsp_search` appended |
| 68288 | 14 | `lfsp_fsname` placement |
| 68415–68420 | 12 | carried |
| 68726, 68727 | 3 | carried |

68094 (PS18), 68095 (PS19), 68231, 68616 and 68617 are untouched and were
not re-pushed.

**What CI has to answer**, since the lab could not: whether 131d goes green.
The mechanism behind the stale errno on rocky8.10 is still unidentified —
the control on the 2.2.11/glibc 2.34 VM linked libzpool into `rwv` and 131d
passed anyway. What the fix rests on is that it removes the only difference
between the passing PS17 and the failing PS18 build.

Watch the janitor's `sanity2@ldiskfs+DNE` and `sanity2@zfs` on 68163 first —
it is the lowest of the fifteen, so it answers soonest.

## sanity 131d: libzpool reached every program that links liblustreapi (2026-09-10)

Ten changes failed `sanity2 test_131d` on both backends in the round-23
janitor runs — 68163, 68288, 68415–68420, 68726, 68727 — with

```
sanity test_131d: @@@@@@ FAIL: Short read filed: read or bytes instead of 1572864
```

**It is ours, and deterministic.** Not flaky, not the janitor's heuristic.

### The chain, each link checked

- 68163 **PS17 passed 131d in 9s** (build 69903); **PS18 failed in 93s**
  (69958). The ancestry #1–#10 is byte-identical between the two builds, so
  the only content difference is 68163's own patchset.
- That delta is docs, tests, and the `zpool_kern_set` probe candidate added
  the day before. The build consoles:

| build | `checking zfs libzpool headers usable from userspace...` |
|---|---|
| 69903 (PS17) | `no` |
| 69958 (PS18) | `-DLIB_ZPOOL_BUILD -I/usr/local/usr/include/libspl … -I /usr/local/src/zfs-2.3.2/include` |

- Autotest configures `--disable-shared`, so `PLUGINS` is **false** and the
  arm that compiles backends *in* is live. `liblustreapi.la` linked
  `libscan_zfs_in.la … -lzpool -lnvpair`.
- `rwv_LDADD = $(LIBLUSTREAPI)`, so every test helper dragged libzpool in.

### Why 131d and nothing else

131d's read is short **by design** — 2 MB asked of a 1.5 MB file — so
`rwv`'s `printf("Read error: %s rc = %d", strerror(errno), rc)` always
fires, and the test's `awk '/error/ {print $6}'` only lands on the byte
count while `errno == 0` and `strerror` is the one word "Success".
`read or bytes` means `$6 == "or"`: the fourth word of "No such file **or**
directory". A stale non-zero errno at `main()`. The test is fragile — it
breaks for anyone who adds a constructor-carrying library to liblustreapi —
but that is upstream's, and **the user's call was to hold it, not file it**.

### Three theories killed before the right one

- **Bucket shift.** Our 531 new sanity lines move 131d from line 18431 to
  18763. Compared the sanity2 test lists of the passing and failing jobs:
  byte-identical, same tests, same order.
- **A bad batch of builders.** 68413 was tested in the *same* later batch
  (69956) and passed, so it splits by content, not by time or node.
- **The loader leaving errno set.** Measured: ld.so probing failing paths
  leaves `errno == 0` at `main()`. It is a constructor, not the loader.

**The cross-patch search Maloo cannot do for initial testing:** the janitor
numbers builds sequentially across *all* reviews and each
`gerrit-janitor/<n>/results.html` names its review in the `<title>`. Sweeping
69800–69990 found 113 other-people builds that ran sanity2 and **not one hit
131d**.

### The fix: the backend goes in the programs, not the library

The first attempt — drop the ZFS backend from the no-plugins arm — was
**wrong and was replaced**. §"The CI had no ZFS scan backend" above records
that the third probe candidate was added *deliberately* to stop conf-sanity
302 failing on ZFS; removing the backend sends 300 and 302 back to
`skip "no $ost1_FSTYPE scan backend in this build"`, silently and with no
red. lreview caught the same shape from the other side: with the backend
gone `-DHAVE_ZFS_SCAN` went too, leaving the `#ifdef` machinery in
`liblustreapi_scan_device.c` gated on a macro nothing defines.

What went in instead, as mount.lustre already does with `-lzfs -lnvpair
-lzpool`:

- the five `scan_zfs_*` prototypes gain `LLAPI_SCAN_ZFS_WEAK` in
  `lustreapi_scan_backend.h`, guarded `#if defined(HAVE_ZFS_SCAN) &&
  !defined(PLUGIN_DIR)`. That guard makes it one-sided for free —
  `HAVE_ZFS_SCAN` is liblustreapi's own flag, so `libscan_zfs.c` compiles
  without it and still defines them **strongly**;
- `libscan_zfs_in.la` moves from `liblustreapi_la_LIBADD` to `lfind_LDADD`
  and `llapi_scan_device_test_LDADD`, the two programs 300 and 302 drive.
  `lfind` is sbin and SERVER-only, which is where a libzpool dependency
  belongs;
- `scan_backend_load_zfs()` returns early on `scan_zfs_open == NULL`.

**The weak reference alone does not link the backend in, and the failure is
silent.** A harness said a convenience library would be enough — its objects
are linked in whole — and *the lab build proved that wrong*: libtool hands
`libscan_zfs_in.la` to the link as a plain `.a`, and an undefined *weak*
symbol is not a reason for the linker to extract an archive member. `nm
lfind` still read `w scan_zfs_open` and the binary held no libzpool symbol
at all, so `lfind` would have answered `-ENOTSUP` on a build that has the
backend, saying nothing about why.

Both programs now name one symbol undefined up front,
`-Wl,-u,scan_zfs_open`, which extracts the member that defines it and brings
the other four with it. Measured three ways in the harness: plain archive →
ENOTSUP; `-u` → `T scan_zfs_open`; `--whole-archive` → also works, and is
the heavier instrument.

**This is the reason to build before pushing.** Every generated-makefile
check passed while the binary was wrong.

### Verified on the lab, including what did *not* verify

RHEL 9.7 VM, `--disable-shared` with ldiskfs, zfs and server all on and
`libzpool headers usable = yes` — the same shape as CI. Built `lib/libcfs`,
`lnet`, `lustre/utils`, `lustre/tests` clean under `-Wall -Werror`, then on
the binaries themselves:

| binary | `scan_zfs_open` | libzpool symbols |
|---|---|---|
| `lfind` | `T` (defined) | 2 |
| `llapi_scan_device_test` | `T` (defined) | — |
| **`rwv`** | — | **0** |
| **`lfs`** | — | **0** |

`rwv` — the binary 131d actually runs — carries no libzpool, which is the
whole point. And 131d's own commands against the fixed `rwv` give
`Read error: Success rc = 1572864`, `NOB=1572864`, pass.

**A second stale-binary trap:** the first `nm` after the `-u` change still
read `w scan_zfs_open`, because `make` had not relinked `lfind` — only the
Makefile changed, and automake's link rule does not depend on it. `rm` the
binaries and re-make. Same family as the stale `lfind` in
§"round 18 lab".

**What is NOT proven.** The control — the same `rwv` relinked *with*
`-lzpool -lnvpair`, `ldd` confirming it really depends on `libzpool.so.5` —
**also passes 131d** on this VM. So libzpool's startup does not leave errno
set under ZFS 2.2.11 and glibc 2.34, and the mechanism that produced `or`
on the builders (rocky8.10, glibc 2.28, ZFS 2.3.2) is unidentified.

What stands without it: the built product's *only* difference between the
passing PS17 and the failing PS18 is that liblustreapi — and so every
program linking it — gained libzpool and libnvpair. This change removes
exactly that difference for every binary except `lfind` and the device
test. CI is where it gets confirmed; do not claim the mechanism until it
does.

Generated makefiles confirm `liblustreapi_la_LIBADD` resolves to `-ldl`
(PLUGINS) or `-lext2fs` (PLUGINS_FALSE+LDISKFS) and **no `-lzpool` under any
configuration**, while `scan_osd_zfs.so` still builds wherever plugins are —
which is what ships, `%bcond_without shared`.

### lreview, and one more real finding

3 findings, severity low, $6.37/13m. One was the option-A flaw above. One is
fixed here: conf-sanity 300's OST half gated on `ost1_FSTYPE ==
mds1_FSTYPE`, but `facet_fstype()` reads the facet's own `MDSFSTYPE`/
`OSTFSTYPE` first, so an **ldiskfs OST under a ZFS MDT** is a real
combination that the match-gate left unscanned by a backend that can read
it. It now asks `ldiskfs || zfs` about ost1 for itself.

**Deferred:** the probe is `AC_COMPILE_IFELSE`, so a tree with usable
headers but no linkable libzpool still sets `enable_zfs_scan=yes` and moves
the failure to `make`. Real, but changing the probe again — without a build
that can prove the new behaviour on the builders — is exactly the move that
caused this entry. Next round.

### The re-run, and a struct that had stopped being append-only

lreview was first run against the option-A commit, so it was run again on
the finished one: 5 findings, $7.78/15m. Two were real bugs in the fix
itself.

- **`lfind_LDFLAGS` silently dropped `UTILS_LDFLAGS`.** A per-target
  `_LDFLAGS` *replaces* `AM_LDFLAGS`, and `lustre/utils/Makefile.am:5` sets
  `AM_LDFLAGS := $(UTILS_LDFLAGS)`. `lfind` would have been the one binary
  in the directory linked without it. Now `$(AM_LDFLAGS) -Wl,-u,…`.
- **The commit message named `conf-sanity 302`, which does not exist at that
  commit** — it arrives four patches later with LU-20637. The isolation
  trap: lreview reads each commit alone, and the Gerrit AI, reading whole
  changes, has never caught one of these.
- A dead initializer in `libscan_zfs.c` (`state` is only read after
  `nvlist_lookup_uint64()` wrote it) — fixed.
- **Declined:** adding `ONLY=131d` to Test-Parameters. `PLUGINS` is
  `enable_shared` and the autotest sessions build from the spec
  (`%bcond_without shared`), so they take the dlopen path where the
  condition cannot arise. The build that carries the weak slot is the
  janitor's `--disable-shared` one, which runs all of sanity on every change
  anyway. Said so in the message.

**The fifth was the interesting one, and lreview only saw half of it.**
`lfsp_search` had been *inserted* before `lfsp_got` rather than appended,
moving `lfsp_got` from offset 48 to 56 — against the rule the struct's own
comment states and `scan_param_whole()` implements. Tracing when each field
actually arrived showed the same defect one commit earlier, and worse:

| field | added by | was |
|---|---|---|
| `lfsp_got` | LU-20603 (68094) | — |
| `lfsp_stats` | LU-20606 (68156) | **inserted before `lfsp_got`** |
| `lfsp_search` | LU-20613 (68163) | **inserted before `lfsp_got`** |
| `lfsp_fsname` | LU-20637 (68288) | appended ✓ |

`lfsp_stats` is the more dangerous of the two: the library *writes* through
it, where `lfsp_search` is only read. A caller built against the LU-20603
header passing that `lfsp_size` would have had its `lfsp_got` pointer read
as one of them.

Both moved to the end, so every change is now a pure append:
`lfsp_got` → `lfsp_stats` → `lfsp_search` → `lfsp_fsname`. Free to do while
unlanded and not free after 2.18. The `ends[]` table is `offsetof`-based and
the tests use `sizeof`/`offsetof`, so nothing carried a hardcoded offset;
checked in all 23 commits that define the struct that its field order and
`ends[]` agree.

**It costs five more changes in the push** — amending 68156 respins
68157–68160 — so the round is 15, not 10.

### Run on the VM against a real target

The VM's `/dev/vdb` is `testfs-MDT0000`, stopped — which is the state a
device scan wants, and the scan is read-only, so the fixture is untouched.

- `llapi_scan_device_test -d /dev/vdb`: **7 of 7 pass**, including test6,
  which is the `lfsp_size` negotiation arms — so the struct reorder is
  exercised, not just inspected.
- `lfind --device /dev/vdb -type f`: **496 objects**.
- 131d's own commands on the built `rwv`: `NOB=1572864`.

**The ZFS slot, proved against the unfixed build.** A name without a leading
slash is a dataset, so it goes to the ZFS backend and never reaches
`scan_device_exists()`'s stat:

| build | `nm` | `lfind --device tank/nosuch` |
|---|---|---|
| without `-Wl,-u` | `w scan_zfs_open` | `Operation not supported` (ENOTSUP) |
| with `-Wl,-u` | `T scan_zfs_open` | `cannot open tank/nosuch: No such file or directory` |

The second is libzpool actually running and saying there is no such pool.
**And the unfixed control still scans ldiskfs fine — 496 objects, the same
answer** — which is exactly why that failure mode is silent: everything
looks healthy and only ZFS targets quietly answer ENOTSUP.

Not run, for want of an OST on this VM: sanity 131d through the framework
(its commands were run directly instead) and conf-sanity 300/302. Those are
CI's to answer.

### lreview round 3, and a per-commit build sweep

Third run, on the finished commit: 3 findings, $9.79/18m. **Nothing on the
weak-symbol wiring or the `-u`** — which was the reason for running it, so
that is the answer it was bought for. Two real, one declined.

- **A pool named like a global kstat read as in-use.** The imported-pool test
  was `stat("/proc/spl/kstat/zfs/<pool>") == 0`, but that directory holds
  ~20 global kstats — `zil`, `fm`, `dbufs`, `arcstats` — as **regular
  files**, confirmed on the VM. An exported pool called `fm` would answer
  `-EBUSY` instead of `-ENOENT`, sending the caller to look for a pool that
  is sitting right there. Now `&& S_ISDIR(st.st_mode)`, which is what the
  comment above it already said.

  Shown on the VM after the fix: `/proc/spl/kstat/zfs/fm` is `-rw-r--r--`,
  a regular file, and `lfind --device fm` answers *No such file or
  directory*. The old test would have matched that file and said busy.
- `access()`/`F_OK` reached `libscan_zfs.c` only through
  `<sys/zfs_context.h>`; `<unistd.h>` now listed with the other libc headers.
- **Declined:** that `lfind.8`'s `.TH` date was unbumped. It already reads
  `2026-09-01`, the same date `llapi_scan_device.3` carries, and the page's
  content has not changed since. The finding asserts a fact the file
  contradicts.

**Per-commit build sweep, #6 through #12** — the commits between and around
the two folds, since a fold breaks intermediate commits silently and
"rebased cleanly" is not "compiles". All seven build, including the
conflict-resolved 68288.

Two smaller checks that came out clean: `LLAPI_SCAN_PARAM_MIN_SIZE` is
`offsetof(lfsp_want) + sizeof(lfsp_want)` = 24 and only fields after
`lfsp_padding` moved, so the reorder cannot have changed which `lfsp_size`
values are accepted; and neither man page carries a literal struct
declaration, so there is no field listing to keep in sync with the new order.

## The OSD scanner in the tree, and 21x over stock lfs find (2026-09-09)

One day, on branch `lu-20720` in `lustre-scanfid` (off the round-23 tip,
7 commits, **unpushed**). Measured, not projected.

### What got built

| | commit | state |
|---|---|---|
| **Group A** — the six OSD patches | 4 wip commits | applied cleanly to the series tip once in date order (`itable-readahead` precedes `itable-blockparse`); kernel build green; new iterator symbols in both `osd_ldiskfs.ko` and `osd_zfs.ko` |
| **B1** — `lfu.ko` | `041fd7cbe6` | written fresh from the prototype's structure, filter left out, `lustre_lfu.h` as a clean UAPI header. Builds, loads, `/dev/lfu_scan` appears |
| **C1+C2** — `libscan_kernel.c` | `8eb0dc0e5c` | the third backend, `scan_osd_kernel.so`; an in-service device routes here when `/dev/lfu_scan` exists |

### Verified before measuring

**Routing, by strace:** `lfind --local` opens `scan_osd_kernel.so` then
`/dev/lfu_scan`. It is not the device backend quietly reading a mounted disk.

**The oracle, one target:** MDT0000 scanned through the kernel and as a
device, visible set **57 = 57, diff 0**. With `--internal` the device side
reports 169 more, all IGIF FIDs (`[0x124f9:0x82b3b4f:0x0]`, seq = inode
number) — LMA-less internal inodes the device scanner surfaces and
`osd_iit_iget()` skips by design. Design-osd-scanner §1.1 row 3, confirmed.

### The benchmark

`rhel9.7-server-mgs-mds-clone`, **87,944 files**, predicate
`-mtime -1 -type f`, five alternating pairs, caches dropped before each run.
Stock `lfs find` is upstream `f0978607c5` with no LFU in it.

| arm | median wall | range | user + sys | count |
|---|---|---|---|---|
| stock `lfs find` | **5.394 s** | 5.30–5.45 (±1.4%) | 0.5 + **4.7** | 87,944 |
| `lfind` on the OSD scanner | **0.254 s** | 0.24–0.27 (±6%) | 0.02 + 0.01 | 87,946 |

**21.2× on the median**, with the noise floor an order of magnitude below the
gap. Raw data: `bench-data/2026-09-09/osd-vs-stock-lfs-find.txt`.

**Three things the number is honest about:**

- **It understates the walk's cost.** Single node, so the client is the
  server and the 4.7 s of sys — one ioctl per object — pays no network
  latency. A real client pays RPC round trips on top.
- **It understates the scan's advantage.** No filter pushdown yet: every one
  of 88k records crossed the ring and `lfind` filtered in userspace. B2 removes
  that copy.
- **The predicate had to be chosen.** `-type f` alone measured 88k files in
  **0.08 s** on the walk — that is `d_type` from the dirent, no RPC, i.e.
  readdir, not `lfs find`. `-mtime` forces the per-object gather, which is the
  cost being compared. A benchmark that picked `-type` would have flattered
  the walk by 60×.

**The count difference of 2 is explained, and not ours.**
`[0x200000400:0x1:0x0]` and `[0xe:0x0:0x0]` are nameless MDT objects —
`fid2path` answers ENODATA — that a namespace walk cannot reach. The device
backend reports the same two. That is the LU-20602 classifier limitation,
shared by both LFU scanners and untouched by today's work.

### Scoped out today, and why

- **No filter pushdown (B2).** The compiled `struct lfu_filter` exists only
  out-of-tree; upstream filters through the `lfsp_filter` callback. In-kernel
  pushdown is a new UAPI, not a port.
- **No xattrs across the ring (B3).** The core classifies from `trusted.lma`
  and names from `trusted.link`, both via `so_xattr`. B1 synthesises the LMA
  from the FID and flag bits; nothing else crosses. So no names, layouts or
  SOM sizes through the kernel path yet — which is why the benchmark predicate
  is an attribute one.
- **The target is a module parameter.** One fixed target per load. It bit
  immediately: `lfind --local` found three targets and the kernel scanned
  **the MDT three times** (441 = 3 × 147). Per-open target selection is the
  first thing owed before this leaves the lab.
- **Routing falls back rather than refusing.** An in-service target goes to
  the kernel only when `/dev/lfu_scan` exists; without the module the device
  backends answer as before. LU-20722's stricter rule waits until `lfu.ko` is
  standard on servers, so conf-sanity 301/303 keep passing meanwhile.

### Two traps for the record

`pkill -f "<string>"` inside an ssh command whose own line contains that
string kills the ssh session — twice today. Split the pattern
(`"while read f""id"`) so the command line never contains it.

And `lfs df -i` lags creates by seconds; do not read a stalled population
off it.

## `lfs find` on an offloaded scan: one thing needs redesigning (2026-09-09)

[`design-lfs-find-offload.md`](design-lfs-find-offload.md). Asked after the
scope settled. **Mostly no; in one place emphatically yes.**

**What does not move.** The predicate machinery already generalises — that was
the point of the 2.18 split. `find_prefilter()`, `find_want()` and
`find_decide()` behind `struct find_ctx`, which already copes with no namespace
walked, no descriptors, and resolve-a-FID-or-print-it. So the HLD's "partially
on the server with Filters on the client" is `find_decide()` over records, which
is exactly what `llapi_find_device()` already does.

**Scope is the real problem, and it is new.** A scan enumerates a *target*;
`lfs find` takes a *subtree*. Nothing today expresses a subtree to a scanner —
`lfsp_search` is ZFS vdev directories, `lfsp_max_depth` bounds a walk. So
`lfs find /mnt/lustre -size +1G` offloads to a clear win, while
`lfs find /mnt/lustre/home/alice -size +1G` would enumerate every object on
every MDT and discard nearly all of them — **slower than the walk it replaces**.

The server has the linkea and could test ancestry, but per object, which defeats
the cheap reject that makes pushdown worth having. So `lfs find` needs an
**offload decision rule**, and it should be dull: offload at the filesystem
root, or when asked explicitly, and walk otherwise. A clever proxy that guesses
wrong makes `lfs find` slower than today, which users notice and blame on the
feature.

**Offload is an optimisation, not a mode.** `lfind` refuses predicates it cannot
answer; `lfs find` must never refuse what it accepts today. It falls back to the
walk for `-maxdepth`/`-mindepth`, for an old server, for a declined
negotiation. And the constraint that shapes the code: **once a record is
printed there is no falling back**, so the decision must be complete before the
first line of output, and a mid-scan failure is an error rather than a silent
switch.

**Merge:** output order changes from traversal to inode order interleaved
across MDTs (manual page, not a surprise); an incomplete answer must be loud;
and duplicates under migration cannot be solved by deduplicating four billion
FIDs, so they need a *rule* — still the question for Andreas.

**Two boxes are genuinely new** in the shape: the decision and the merge.
Everything else is already in the tree.

## `osd_iit_iget()` read: attribute capture is free for existing users (2026-09-09)

The last question gating LU-20720's first patch, answered by reading rather
than measuring. **Free, and the `rec-attr` patch already has the right shape.**

`osd_iit_iget()` has exactly two callers, already distinguished by a boolean:

| caller | who | `is_scrub` |
|---|---|---|
| `osd_scrub_next()` | OI Scrub and LFSCK | `true` |
| `osd_preload_next()` | the otable iterator | `false` |

Four gates keep the cost off everyone who did not ask:

1. the scrub call site passes `NULL` for the attribute out-parameter
2. the capture is `if (la != NULL && rc >= 0)` — scrub never enters it
3. the otable call site passes NULL too unless `dev->od_otable_it->ooi_want_attr`,
   so an otable consumer that asked for a bare FID (LFSCK, `attr == 0`) also pays
   nothing
4. and when it *does* run, the inode is already instantiated between
   `osd_iget()` and `iput()` — the capture is nine field copies off a hot
   cacheline, no extra I/O

**The structural choice is the one that matters most, and it was made right.**
The attributes go in a *parallel* array, `struct lu_attr ooc_attr[64]` inside
`osd_otable_cache`, **not** by widening `struct osd_idmap_cache`. That struct
has 14 uses in `osd_handler.c`, including `oti_ins_cache`, the per-thread insert
cache on the transaction path — widening it would have taxed the whole OSD to
serve the scanner. Cost as built is ~100 B × 64 ≈ 6.5 KB **per otable
iterator**, not per object.

**And the question turned out smaller than its framing.** Block parsing took the
fast path off `osd_iit_iget()` entirely — `osd_iit_iget_raw()` reads the inode
table directly and never builds an inode — so this function is now the
*fallback* for what raw parsing cannot decode, plus the singleton path. The
answer is still needed, because the fallback has to produce records identical to
the raw path, but it is not the hot path any more.

**Nothing now blocks A1.**

## LU-20720, LU-20721, LU-20722 filed: the 2.19 work (2026-09-09)

| | |
|---|---|
| **LU-20720** | `LFU: in-kernel OSD scanner` — the engine. Iterator attributes, private parallel iterators, block parsing, readahead, xattrs, in-kernel filtering |
| **LU-20721** | `lfs find` offloaded to the servers — the client sends the search, servers scan and filter, records stream back. Depends on LU-20720 |
| **LU-20722** | `lfind` on a live target — the third `llapi_scan_device()` backend, reading the stream instead of the device. Depends on LU-20720, independent of LU-20721 |

**Build order is LU-20720, then LU-20722, then LU-20721.** LU-20722 is not on
the client-side path, but it is the *only practical correctness oracle for
LU-20720*: one quiescent target scanned as a device and through the kernel,
answers compared object by object. It also exercises the Object Stream API
against a local consumer before a client depends on it across a wire, which
takes risk out of LU-20721.

All three Technical tasks under LU-20462, all Open. Drafts in
[`docs/tickets/`](tickets/), design in
[`design-osd-port.md`](design-osd-port.md).

**The scope was settled by the tool names.** `lfs find` runs on a client and
`lfind` runs on a server, so "`lfs find` on the OSD scanner" can only mean the
client sending the search to the servers — the HLD's Server and Client Bulk RPC
Filter Rule Modules, not a third backend under `llapi_scan_device()`.

**LU-20721's summary was filed with the older server-local wording and has
been corrected** to `LFU: 'lfs find' offloaded to the servers over bulk RPC`.

**fixVersion stays empty, and that is correct.** There is no 2.19 version in
the LU project — the only unreleased ones are `Upstream`, `Lustre 2.18.0` and
`Lustre 2.15.9`, and 2.19 is created when its cycle opens. Checked: **no
LU-20462 subtask sets fixVersion at all**, nor the epic, nor LU-20591. The
drafts asking for 2.19 were wrong about the convention; they now record the
release target as prose instead.

**Markup verified rather than assumed**: `?expand=renderedFields` shows 9 and 7
`<h3>` tags and 23 and 5 `<tt>` spans, with no literal `h3.` or `{{` left. The
discipline from [[jira-wiki-markup]] held.

### What the HLD re-read added

Reading `docs/local/Lustre_Find_Utility-High_Level_Design.pdf` rather than
recalling it settled four things:

- the client uses **the same Object Stream kernel API as the OSD**, fed by
  **bulk RDMA** — the ring is the API at both ends, not a local-only detail, and
  no opcode is named
- negotiation is **per-scan as well as per-connection**, and "partially on the
  server with Filters on the client" is explicit — so the residue mechanism is a
  requirement
- access control is specified: POSIX UID/GID/ACL, **filesets and nodemaps**,
  filtered server-side. The failure mode here is a disclosure, not a wrong answer
- the HLD phases it itself — **administrators from a client first, regular users
  later** — which defers permission filtering without deferring transport

**And it puts the wire format on the critical path.** The HLD asks for an
extensible binary format rather than monolithic structures; our record is a
fixed 168-byte struct. [[lfu-wire-format]] was deferred on 2026-08-19 as
not-ours and never evaluated. It needs an owner before the record is committed
to.

### Still open

- **duplicate FIDs across merged streams** while a file migrates — unanswered in
  every HLD revision, and it gates the merge
- **where `DOIF_NOSCRUB` comes from.** LU-20591 is no longer a collision —
  Jinshan has decided to follow LFU — so there is no rival interface to
  sequence around. But that series is where `DOIF_NOSCRUB` lives, and it is the
  one piece of it LU-20720 depends on: confirm whether it lands there with
  attribution, or we carry it

## Next: porting the OSD scanner into Lustre (2026-09-09)

Design written, no code: [`design-osd-port.md`](design-osd-port.md).

**The seam already fits.** `src/lfu_scan_kmdt.c` implements
`open/close/worker_init/worker_fini/scan_chunk`; the plugin interface that
shipped in round 23 is `sb_open/sb_close/sb_worker_init/sb_worker_fini/
sb_scan_chunk`. Same five entry points, arrived at independently. So the kernel
scanner becomes a **third backend** beside ldiskfs and ZFS, and everything above
`llapi_scan_device()` — the predicates, `lfind(8)`, `--fid2path`, `--paths`, the
man pages — is unchanged. What it buys is the one thing neither device backend
can do: **scan a target that is still in service.**

**Four decisions, with recommendations:**

- **The Jinshan collision.** LU-20591 (68018/68019/68020) is still `NEW`, 68019
  and 68020 untouched since 08-31 and 08-14. The old plan — build `DOIF_ATTR`
  under their `scrub_iterate_objects()` — would make our landing date theirs.
  Recommend instead separating the **OSD-layer work from the UAPI** and landing
  the OSD layer alone: it speeds their walk too (they pay `dt_locate()` +
  `dt_attr_get()` per object), so it is cooperative rather than rival.
- **The wire record stays `lfu_wire_rec`**, not `llapi_scan_rec`: 168 B vs
  504 B is 239 MB/s vs 716 MB/s at the measured 1.42M obj/s, and the API record
  carries pointers that cannot cross the boundary.
- **Filter pushdown in v1, tier 0 first.** Without it `--size +1G` over 4e9
  objects copies 672 GB to find a thousand. Tier 1 waits for `DORA_XATTR`.
- **`lfu.ko`, and the kernel owns the parallelism** — the prototype already
  forces `-j 1` for the reason.

**"Make `lfs find` work with it" is three different things** (§4): `lfind` on a
live target (L1, nearly free given the seam), `lfs find` on a server (L2), and
`lfs find` on a client offloading to every MDT over `OBD_IDX_READ` (L3, the
HLD's actual design and about the size of everything done so far). **L1 vs L3 is
the user's call and changes the work by an order of magnitude.**

**First moves, none of them code:** settle "cost to existing users" by reading
`osd_iit_iget()`; put the group-A split to Andreas and Jinshan; decide L1/L3.

## The ZFS arm run: the last gap closed, no change needed (2026-09-09)

Round 23 was pushed with one arm unexercised — 304's ZFS half, the whole
reason the test exists. It has now been run and it passes.

The lab VM already had **ZFS 2.2.11** installed by DKMS, with `libzpool`
headers and a source tree at `/usr/src/zfs-2.2.11`, so no ZFS build was
needed. Lustre rebuilt from the pushed tree with `--with-zfs`.

**`--with-zfs-obj` is required on a DKMS host.** The first configure said
`zfs build directory... Not found` and disabled osd-zfs: DKMS keeps
`zfs_config.h` under `/var/lib/dkms/zfs/<ver>/<kernel>/x86_64/`, not in the
source tree, and the m4's DKMS branch only looks there when `zfssrc` is
`${zfsdkms}/source`. Ours came from `/usr/src/zfs-2.2.11` instead. Not our
bug and not worth a patch, but it costs an hour if you meet it cold.

### What the build itself proved

```
checking zfs libzpool headers usable from userspace... -DLIB_ZPOOL_BUILD
  -I /usr/src/zfs-2.2.11/lib/libspl/include ... -I .../include/os/linux/zfs
```

The check succeeded on a **real Lustre configure**, taking candidate 1 —
`/usr/src/zfs-2.2.11` is a genuine source tree, so the source set applies.
`scan_osd_zfs.so` was built and installed to `/usr/lib64/lustre/`. That is
the regression case worth having: the m4 change does not break a normal ZFS
build, and the backend still enables where it should.

### The run

`FSTYPE=zfs`, all three, and each did real work rather than passing on a
guard:

| | ZFS | ldiskfs |
|---|---|---|
| **300** | `--internal added 318 objects` | 255 |
| **302** | `offline --fid2path named 20 objects by their owner` | same |
| **304** | **`offline --paths named 20 objects on zfs`** | `on ldiskfs` |

304 scanned `lustre-mdt1/mdt1` with the pool exported, which is the
`export_zpool` + `--search $(dirname $(mdsvdevname 1))` path that had never
executed. The only skip in the run was the framework's own `SLOW=no` list.

**No code change came out of it** — the tests pass exactly as pushed.

**Still not covered:** ZFS **2.3.x**. This VM is 2.2.11, so the `abd_os.h`
case the configure fix was written for is proven only by the rocky8.10
reproduction, where the packaged candidate failed and the new one succeeded.
Autotest runs 2.3.2 and is where that path first executes for real.

## Round 23 PUSHED: 11 changes (2026-09-09)

Pushed off `5afbab284e`. Ten of the twenty stacked changes were byte-identical
to Gerrit and took no new patchset; 68413 went up as a sibling, as before.

| | |
|---|---|
| **New patchset** | 68163 PS18, 68288 PS13, 68415 PS11, 68416–68420 PS11, 68726 PS2, 68727 PS2 |
| **Sibling** | 68413 PS7 |
| **Untouched** | 68616, 68617, 68231, 68094, 68095, 68156, 68157, 68158, 68159, 68160 |

What went up: the three fixes for round 22's red (test17's registration, the
ZFS configure candidate, 157d's `-m ALL`), the 27 lreview findings across two
passes, and the two the VM found. 68413 delivers the comment folds its three
answered AI threads promised.

**Everything that could be run, was**: sanity 157c (10 cases) and 157d (8),
conf-sanity 300, 302 and 304, all passing on a real single-node filesystem
built from this tree. The one arm still unexercised is 304's ZFS half, which
needs a ZFS lab; autotest is where it first runs.

Expect the Merge Conflict banner on the stacked changes and LU-20598
`sanity-sec`. `gpoll.py` already covers every id here.

## The VM run, then lreview again: 11 more findings (2026-09-09)

Tested before reviewing, on the user's instruction, and both halves paid.

### The VM: everything passes, and it found two things reading could not

Our tree built and installed on `rhel9.7-server-mgs-mds-clone`, a real
single-node filesystem (MDT, two OSTs, client).

| | |
|---|---|
| sanity **157c** | PASS, 10 cases — first execution ever |
| sanity **157d** | PASS, 8 cases — after one real fix |
| conf-sanity **300** | PASS — *"--internal added 255 objects"* |
| conf-sanity **302** | PASS — *"offline --fid2path named 20 objects by their owner"* |
| conf-sanity **304** | PASS — *"offline --paths named 20 objects on ldiskfs"* |

**A stale `/usr/bin/lfind` from Sep 6** sat beside the fresh install, and
`which lfind` is how conf-sanity 300, 302 and 304 find it. Removed. This is
[[lfu-scan-plugin-trap]] in a new spelling: the thing on the path beats the
thing you built, and the test says PASS either way.

**test0 failed: "no CL_MKDIR in the stream".** 157d makes its directory with
`lfs mkdir -i 0` *before* `changelog_register`, so that CL_MKDIR falls
outside the user's window, and `make_events()` then hit EEXIST and never made
another. Every other event type was present, which is why one assertion fired
and not four. Fixed in the binary rather than by reordering the shell:
`make_events()` now makes a directory of its own, named for the pid, so it no
longer depends on the caller's sequencing.

**The LU-20647 workaround is proven** — no "cannot set changelog filter"
anywhere in the run.

### lreview round 2

**68163 — one finding, a real defect.** `scan_backend_kind()` routed by stat
*type*: block device or regular file to ldiskfs, everything else to ZFS. So
any existing path that is neither — a mount point, a directory, a character
device — was read as a dataset name. Measured on the VM: `lfind --device
/tmp` answered **"No such file or directory"** for a path that plainly
exists, the ZFS backend having cut the name at its first slash. A leading
slash now routes to ldiskfs before the stat, because a pool name cannot
begin with one, and the same command answers **"Is a directory"**.

**68288 — five findings, all low; the reviewer said no functional defect.**
Two were ours from adding test_304 (the commit message never mentioned it,
and a stray blank line). One was a real gap: striped-directory shards are a
whole component the message never described — `LLAPI_SCAN_LMV_SHARD`, the LMV
the pre-pass now pays for, and the empty-named map entry `scan_dirmap_path()`
steps through. Two were placement: `scan_lmv_is_shard()` had been inserted
between `scan_lmv_to_user()`'s block comment and that function, and `parent`
was dereferenced in an initializer above the check meant to validate it.

**68415 — five findings, and one was ours.**

`sc_got` — added in round 1 to answer a reviewer — **was dead on arrival**.
`SCAN_CLF_END(sc_got)` was missing from the size list, so
`scan_cl_param_whole(104)` returned 96 and the copy stopped one field short:
`sizeof` 104, `offsetof(sc_got)` 96, largest entry `sc_stats` 96. The field
was NULL for every caller however they set it.

**test7 now asserts it comes back**, and was proved against the unfixed
build per [[lfu-lift-and-compare]]: with the list entry removed, 157d fails
`sc_got came back 0`; with it restored, it passes.

Two real `_CLEAR` defects, both pre-existing: `scan_cl_flush()` and the
eviction path each did unlink, deliver, free unconditionally, so an object
the consumer *refused* left the cache anyway and stopped being counted by
`scan_cl_held_first()` — and `scan_cl_clear()` then purged records nothing
had accepted, which a restart from `sc_startrec` cannot read back. Both now
deliver first and unlink only on success; `sl_aged` is drained at teardown,
so an object left linked is still freed.

**One finding declined.** It claimed 157d leaks its changelog user because
`changelog_register()` "only stack_traps the changelog_mask restore". It does
not: that function's line 23 is `stack_trap "__changelog_deregister $facet
$cl_user" EXIT`, and the VM run printed *"Deregistered changelog user #1"* at
teardown. Wrong on the code and on the evidence.

### What this says about the order

The second review found a bug **in the fix the first review asked for**.
Pushing after one pass would have shipped a field that could never be filled,
with a man page describing it.

## lreview before the push: 16 findings, all fixed (2026-09-09)

Run on the three changes with new content — 68163, 68288, 68415 — one at a
time, ~$8 and 12-19 minutes each. **Not one finding was about the three fixes
that prompted the round**; lreview reviews the whole commit, so these had all
survived their patchsets. That is the argument for running it: round 22 went
up without it and came back red three ways.

### 68163 — 3 findings, severity low

`sp_search` in the commit message where the field is `lfsp_search`, and it
appears nowhere in the tree as a standalone token — a leftover from the
`lfsp_` rename. `llapi_scan_device_test.c` asserted `rc < 0` for a missing
device where `-ENOTSUP`, the answer *before* the patch, passes too; tightened
to `-ENOENT` after linking against the built library and measuring it (**−2,
not −95**). `sb_open()`'s new `search` parameter documented in the struct's
block comment.

The "no single home" remark had one: `llapi_find_device.3` omitted `-EBUSY`,
`-EMEDIUMTYPE`, `-ENODEV` and `-E2BIG`, and **all four are introduced by
68163 itself**, so ERRORS grew there.

### 68288 — 7 findings, severity medium, three of them real

**The functional gap.** `llapi_find_device()` copied `lfsp_fsname` in and
passed `mfs[0] ? mfs : NULL`, so the `-EXDEV` its own man page documents
could not fire for a `--paths` caller. Now falls back to `spl.lfsp_fsname`.

**Sweep state leaked.** `scan_device_sweep()` reset the cursor and the stop
but not `sd_end`, which a worker *lowers* when it sees the last chunk — so
the search inherited the pre-pass's bound. On an in-service MDT (conf-sanity
301 and 303) an object allocated between the sweeps fell outside the search
silently, not even in `ss_skipped`.

**The header broke its own rule.** `lfsp_fsname` went in ahead of `lfsp_got`,
moving it, against "a field appended here does not break the applications
that do not use it". Measured after the move: `lfsp_got` is back at offset
56, `lfsp_fsname` appended at 64, `sizeof` 72. An old caller's `lfsp_size` of
64 now falls short of the 72 that gates `lfsp_fsname` and reads it as NULL —
where before it passed the gate and had its `lfsp_got` pointer `strlen()`'d
as an fsname.

Plus the dead OST early-return in `scan_dirmap_cb()` (the label gates the
pre-pass to MDTs, so it never fires — and would fail the whole call if it
did), the `scan_dirmap_path()` comment claiming fid2path answers with a
leading '/' when `mdt_path_current()` steps over it, and two commit-message
paragraphs describing a two-open design the patch does not have.

### 68415 — 6 findings, severity medium

**The O_PATH answer was never lazy.** `ll_getattr_dentry()` glimpses unless
`AT_STATX_DONT_SYNC`, O_PATH is invisible to `->getattr`, and `lli_lazysize`
is substituted only under that flag — so `fstat()` on the O_PATH fd bought a
strict size that was then labelled `LLAPI_SCAN_LAZY_SIZE`, and the second
open bought nothing. `scan_cl_mdt_stat()` now uses `statx(AT_STATX_DONT_SYNC)`
and reports `*lazy`; without `HAVE_STATX` there is no way to ask, so the
fallback says the answer is strict rather than mislabelling it.

`sc_size` larger than the struct with a zero tail is now accepted, as
`scan_param_copyin()` does for the two sibling entry points. The unreachable
`sc_user` test in the clear path is gone. `sc_got` is appended — `sc_padding`
is a `__u32` and cannot hold a pointer — so one consumer can ask all three
scanners what they will answer for.

**And the comment beside the round's own 157d fix was wrong.** "-u is for the
cases that clear" — there were no clearing cases. It now says `-u` puts the
read on `llapi_changelog_start_user()`, the path that sets the server-side
filter, which is exactly the path LU-20647 breaks and exactly why the
registration needs `-m ALL`. The two now explain each other.

### The coverage both reviewers asked for

`llapi_scan_changelog_test` **test6** gives `_CLEAR` its first positive
coverage — it was named only in test4's `-EINVAL` case, so nothing exercised
`scan_cl_clear()`. It asserts on indices, not counts: a later scan may not
deliver a record at or below the last index the clearing scan took. Counts
would not say it, because the test's own workload keeps adding records.

**conf-sanity 304** is the offline half of 303. 303 reads an MDT in service,
which only ldiskfs allows, so the `--paths` pre-pass had never run on ZFS.
304 stops the MDT and exports the pool, which is the one state both backends
share.

**Unrun, and that is now five.** 157c, 157d, conf-sanity 300, 302 and 304,
plus `llapi_scan_changelog_test` test6. Autotest is where they first execute.

## Round 23 prepared: 11 changes, half the stack untouched (2026-09-09)

Not pushed. Three fixes folded into the series, plus 68413 PS7.

**68413 gets its PS7 rather than a BUILD.** Its `Verified-1` is noise on both
counts: `sanity-sec` is LU-20598, and the `sanityn` failure on
review-dne-part-5 cannot be this patch — `sanityn.sh` never mentions
changelogs, and 68413 touches only `mdd_changelog_user_lookup_cb()` and its own
`sanity.sh` case. A retest would likely clear it. But the 09-02 AI review left
three comments, **all three already answered with "Lands in the next
patchset"**, and those changes were sitting on `lu-20647-r18` undelivered.
Retesting PS6 would spend a full round on a patchset about to be superseded;
pushing PS7 retriggers everything anyway and delivers what was promised.

The earlier reason for holding 68413 — functionally identical to PS6, "two
relocated comments" — has been overtaken: those relocations *are* what the
review asked for.

**The commit message took the middle path.** PS6 was 60 lines and the AI called
it too long for a 15-line change; `lu-20647-r18` cut it to 44 but dropped two
things worth keeping. PS7 is 53: it opens with what the patch does, and keeps
both *"every other MDD walker already takes both types"* and *"only the
`cf_user_id != 0` path changes behaviour ... the client parses `cl<N>` into an
ID"*, which is what a reviewer needs to size the risk.

**PS7's non-comment diff against PS6 is empty**, so PS6's jenkins `Verified+1`
carries. The two stacked comment blocks the fold left behind are merged into
one.

### What the push spends

Ten of the twenty stacked changes are byte-identical to what is on Gerrit and
take no new patchset:

| | |
|---|---|
| **New patchset (10)** | 68163→PS18, 68288→PS13, 68415→PS11, 68416→PS11, 68417→PS11, 68418→PS11, 68419→PS11, 68420→PS11, 68726→PS2, 68727→PS2 |
| **Untouched (10)** | 68616, 68617, 68231, 68094, 68095, 68156, 68157, 68158, 68159, 68160 |
| **Sibling** | 68413→PS7, off `5afbab284e` as before |

The push is two commands, because 68413 is not in the chain:

```
git -C lustre-scanfid  push review lab/spgot:refs/for/master
git -C lustre-lu20647  push review HEAD:refs/for/master
```

Expect the usual Merge Conflict banner on the stacked changes and LU-20598
`sanity-sec` noise. **Still unrun:** 157c, 157d, conf-sanity 300 and 302.

## sanity 157d: register with a mask, not a restack (2026-09-09)

157d failed on every config with

```
llapi_scan_changelog_test: cannot set changelog filter: No such file or directory (2)
```

**The board's earlier note was out of date on one point.** The upstream bug is
not unfiled: it is **LU-20647 / 68413**, at PS6 with adilger's `Code-Review+1`.
The trouble is where it sits. 68413's parent is `5afbab284e` — our series' own
base — so it is a *sibling* of the chain, not an ancestor. Autotest for 68415
builds the base plus 68094..68415 and never sees it, so 157d runs against a
server that still has the bug.

**Restacking was rejected.** Putting 68413 under 68094 rewrites every commit
above it: twenty new patchsets, ~30 test sessions each, to work around a
placement. Against [[gerrit-etiquette]] and [[gerrit-push-cadence]] both.

**What the test actually needs is a changelog user the MDD can find.**
`mdd_changelog_user_register()` (`mdd_device.c:1789`) picks the record type
from its arguments: `mask || name` gives `CHANGELOG_USER_REC2`, and nothing
gives the old `CHANGELOG_USER_REC`. The unfixed lookup matches only `REC2`.
So `changelog_register -m ALL` produces a user the *unfixed* server can find,
and `ALL` is `CHANGELOG_ALLMASK`, so nothing the test expects is filtered out.
One line in 157d, and 68413 keeps its own 69-line test for the bug itself.

**Scope is 157d alone.** Five tests in the stack register a changelog user —
157d, 160aa, 160ab, 160ac, 160ad — but `lfs.c` never sets `sc_user`, so
`lfs find --since/--changelog` takes `llapi_changelog_start()` and never
issues the filter ioctl. Only 157d passes `-u`. That is exactly what the CI
reported: 157d red, the 160a* series untouched.

### Measured on a real MDD, and where the chain stops

`rhel9.7-server-mgs-mds-clone`, MDT mounted, both registrations run:

```
cl1                               0 (1)
cl2                               0 (0) mask=MARK,CREAT,MKDIR,...,NOPEN
```

`cl1` is the plain register — **no mask, so a `CHANGELOG_USER_REC`**. `cl2` is
`-m ALL` — the full mask, so a `REC2`. The exact argument order test-framework
generates (`changelog_register -n -m ALL`) is accepted by both the old and new
`lctl` spellings; they share `jt_changelog_register`.

**Not run, and worth saying:** that the *unfixed* lookup accepts the `REC2` the
new registration makes. Its condition is a single `lrh_type !=
CHANGELOG_USER_REC2 → skip`, so it does — but that is a code read. Showing it
would mean building an unfixed server; the lab's tree already carries the fix,
and `lfs changelog --user` there could not reach the filter at all without a
client mounted. The other half needs no proof: the CI *is* the unfixed server,
and it answered ENOENT for a plainly-registered user.

## The CI had no ZFS scan backend: ZFS 2.3 moved a header (2026-09-09)

conf-sanity 302 failed on every ZFS config with

```
lfind: lustre-ost1/ost1: Operation not supported
```

Not the test, not `--search`. The janitor's own build console says it:

```
checking zfs source directory... /usr/local/src/zfs-2.3.2
checking zfs devel headers... -I /usr/local/usr/include/libspl -I /usr/local/usr/include/libzfs
checking zfs libzpool headers usable from userspace... no: llapi_scan_device will have no zfs backend
```

`ZFS_SCAN_ENABLED` was off, so `scan_backend[SCAN_BACKEND_ZFS]` was NULL and
`scan_device_run_prepass()` returned `-ENOTSUP`. ldiskfs 302 passed
throughout; only ZFS failed, on every ZFS session.

### Two causes, and the first hypothesis was wrong

The guess was that the source-tree candidate omitted `-I $zfsobj`, the build
directory holding `zfs_config.h`. **Measured against real ZFS 2.3.2 sources:
false** — that candidate compiles clean without it, even under `-Wall
-Werror`. The truth is two things at once:

1. **`/usr/local/src/zfs-2.3.2` is not a source tree.** ZFS installs its
   kernel headers to `kerneldir = $(prefix)/src/zfs-$(VERSION)/include`, which
   with `--prefix=/usr/local` is exactly that path. Our guard tests
   `$zfssrc/include/os/linux/zfs`, a source-tree-only path, so the source
   candidate was never tried.
2. **ZFS 2.3's `sys/abd.h` includes `sys/abd_os.h`**, and upstream installs
   `abd_os.h` *only* into the kernel header tree — never into the userspace
   devel headers (`include/Makefile.am`: `nobase_libzfs_HEADERS = $(COMMON_H)
   $(USER_H)`, while `abd_os.h` is in `kernel_sys_HEADERS`). So the packaged
   candidate died on `sys/abd.h:34: fatal error: sys/abd_os.h`. 2.2.2's
   `abd.h` does not include it, which is why this never showed up locally.

### The fix, and it is measured on all three layouts

A third candidate pairing the packaged devel headers with `$zfssrc/include`.
Verified by regenerating `configure` from the changed m4 and running the
generated logic against a faithful 2.3.2 install built from the release
tarball:

| layout | candidate | before | after |
|---|---|---|---|
| real 2.3.2 source tree | 1 (source) | yes | yes |
| packaged 2.2.2, no `$zfssrc` | 2 (devel) | yes | yes |
| **the CI: kerneldir + devel, 2.3.2** | **3 (new)** | **no** | **yes** |

`aclocal -I config && autoconf` regenerates cleanly and the new branch reaches
the generated `configure`.

**conf-sanity 302 also gets the skip test_300 already has.** A build whose
configure found no headers legitimately has no backend, and `-ENOTSUP` is that
build rather than a target the scan could not read. 302 failed hard where its
sibling skips; it now matches.

### Proved on a Rocky 8.10 VM, and the CI's own config.log

The workstation reproduction used a *fake* install tree and gcc 13. Two things
were still guesses, and both were checked properly.

**The CI's `config.log`, pulled from `source-and-binaries-rocky8.10-x86_64.tar.xz`,
is the ground truth:**

```
configure:20716: gcc -c -g -O2 -Wall -Werror -Wno-gnu -D_GNU_SOURCE -DLIB_ZPOOL_BUILD
  -I/usr/local/usr/include/libspl -I/usr/local/usr/include/libzfs
  -I/usr/local/usr/include/libzpool conftest.c >&5
/usr/local/usr/include/libzfs/sys/abd.h:34:10: fatal error: sys/abd_os.h: No such file or directory
```

`config.status` confirms the consequence: `ZFS_LIBZPOOL_INCLUDE=""`. And there
is **exactly one** `LIB_ZPOOL_BUILD` compile in the whole log — the packaged
set. The source candidate was never tried, so `$zfssrc/include/os/linux/zfs`
does not exist on the CI, which is what a source tree would have.

**`rocky8.10-mgs`, gcc 8.5.0 — the CI's own compiler.** ZFS 2.3.2 built from
the release tarball and installed twice to reproduce the layout: kernel
headers flattened into `/usr/local/src/zfs-2.3.2/include` (so
`include/sys/abd_os.h` exists), userspace devel headers under
`/usr/local/usr/include` (so `libzfs/sys/abd.h` exists and `abd_os.h` does
not), `include/os` removed to match the guard's failure on the CI.

Then Lustre's **real `configure`**, twice, same tree, only the m4 swapped:

| arm | `checking zfs libzpool headers usable from userspace...` |
|---|---|
| unfixed | `no: llapi_scan_device will have no zfs backend` — **the CI's line verbatim** |
| fixed | `-DLIB_ZPOOL_BUILD -I…libspl -I…libzfs -I…libzpool -I /usr/local/src/zfs-2.3.2/include` |

And the last link, which a passing probe does not establish: **`libscan_zfs.c`
itself compiles** under gcc 8.5 with exactly the include set the fixed
configure chose, clean under `-g -O2 -Wall -Werror`. Without that, enabling
the backend could have turned a silent skip into a build failure across all
twenty changes.

**One hypothesis died on the way.** Candidate 1 was thought to be failing under
gcc 8; on a pristine 2.3.2 source tree it passes in every flag combination
tried. It was never *run* — the guard skipped it.

**Still unproven:** that `$zfssrc/include/sys/abd_os.h` exists on the CI
specifically. It is inferred, not observed: `osd_handler.c` includes
`<sys/spa.h>`, which reaches `abd.h` and so `abd_os.h`, and osd-zfs compiles
there while `include/os/linux/zfs` is absent — so `-I$(ZFS)/include` must be
supplying it. Should that inference be wrong, the new candidate is inert and
the CI keeps skipping, which is where it already is.

## test17 registered where it is defined: five Verified-1 cleared (2026-09-09)

Round 22 came back red three ways. This is the first: 68416, 68417, 68418,
68419 and 68420 all failed to build on rocky8.10 and rocky9.6 with

```
llapi_scan_test.c:736:13: error: 'test17' defined but not used [-Werror=unused-function]
```

`test17()` was added by `bf080a686a` (68416, *fill a scan record for one
FID*), but the `TEST_REGISTER(17),` that references it sat five commits
higher, in `19d5361893` (68726, the batch API). Every commit in between had
an unused static. The Verified-1 boundary matched exactly: 68415 below it
built, 68726/68727 above it built, the five between did not.

**The fix is the one line moved down**, so each test case is registered in the
commit that defines it. 68416 now adds `test17` *and* `TEST_REGISTER(17)`;
68726 adds 11–16 and no longer touches 17. The intermediate table reads
`0..10, 17` for five commits, which is transient and correct.

**The finished tree is byte-for-byte unchanged** — `git rev-parse
lab/spgot^{tree}` is `c2be1235` before and after, as [[lfu-stack-rename-split]]
prescribes. Only the distribution across commits moved.

### Why the sweep missed it, and what that cost

`tests/build-sweep.sh` checked the test programs with `gcc -fsyntax-only`.
**gcc runs the unused-function analysis at the end of code generation, so
`-fsyntax-only` cannot see this class of error at all** — adding `-Wall
-Werror` to it changes nothing, as measured: the unfixed stack passes a
`-fsyntax-only -Wall -Werror` check at all twelve commits.

The sweep now compiles for real (`gcc -c -o /dev/null -Wall -Werror`).
Proved against the unfixed build per [[lfu-lift-and-compare]]: the corrected
check reproduces the CI's error text at line 736 on exactly the five commits
Gerrit marked Verified-1, and is clean on all eight of the fixed stack.

Full sweep after the fix: 20 commits, `build=0 hdr=0 tests=0` on every one.
checkpatch on both touched commits is clean but for the usual MAINTAINERS
warning.

## Round 22 PUSHED: 20 changes, two of them new (2026-09-08)

Pushed to Gerrit as `refs/for/master` off `5afbab284e`. Eighteen changes got a
new patchset; **two are new numbers**, the work built after round 19:

| | |
|---|---|
| **68726** | `LU-20603 llapi: pull a scan's records in batches` — the `llapi_scan_next()` layer |
| **68727** | `LU-20605 llapi: trim a start point's trailing slashes` |

Both are added to `tests/gerrit-poll/gpoll.py`. A change missing from that list
is invisible to the watch, which is how 68340 stayed out of a morning check.

The stack now reads 68616, 68617, 68231, 68094, 68095, 68156, 68157, 68158,
68159, 68160, 68163, 68288, 68415, 68416, 68417, 68418, 68419, 68420, 68726,
68727 — 68094 at PS18, 68095 at PS19, the changelog six at PS10.

What went in: the whole of round 22 — the lreview sweep's 70 findings, the
three commits that did not compile, `find_prefilter()`'s bool and
`find_decide()`'s 0/-errno, `llapi_scan_fid()` reading through `mnt_fd`, the
trim consolidated into `llapi_find_with_cb()`, and the four test gaps.

**Owed:** the new tests have not been run. 157c, 157d and conf-sanity 300 need
a lab; only the lifted `test14` has executed. Expect the usual Merge Conflict
banner on the stacked changes, and LU-20598 `sanity-sec` noise.

## The missing test coverage, four of five closed (2026-09-08)

Last of the open lreview findings. Four gaps closed, each in the commit that
introduces what it tests; the fifth — a direct API test for
`llapi_find_device()` — turned out not to be a gap.

**The `-EBUSY` case could not fail.** `test14` asked for a second consumer
between two `llapi_scan_next()` calls, where the guard does not apply, so the
ASan overflow the guard exists for was never in reach. It now *makes* the
window: a filter that sleeps holds the scan back so the consumer's third call
blocks — two calls first, the layer filling one batch ahead — and the overlap
is **measured**, not assumed. A machine too slow to land the second call
inside the window reports the case as unreachable rather than failing.

Proved off Lustre by lifting the harness's Lustre gate (see
`tests/lift/README.md`): eight runs, `-EBUSY` every one, 0.8s each because the
filter really held the scan. **Before the rework the same run took 2ms** and
never reached the guard — which is exactly the reviewer's point, measured.

**`llapi_scan_fid()` gets `test17`**, so sanity 157c runs it: one record for a
known FID checked against the client's pathname and basename, a filter that
skips (a success with nothing delivered), the argument refusals including the
`-EBADF` a negative `mnt_fd` must answer rather than the `-EINVAL` that also
means *this FID has no name*, `lfsp_thread_count > 1`, and a FID that resolves
to nothing.

**`llapi_scan_changelog_test` was built and never run.** sanity 157d runs it,
making its directory on MDT0 itself rather than leaving the binary to notice
that a DNE mkdir below a striped root put its events in another MDT's log.

**conf-sanity 300 covers `--internal`, `--local` and `--target`.**
`--internal` is the same scan without the class filter, so the answer without
it has to be a subset and strictly smaller — a target reporting none of its
own objects passes a count test and fails the point. `--local` and `--target`
are checked where the suite has already stopped everything: each must name the
target it could not find rather than scan something else.

**Not a gap:** `llapi_find_device()` has no direct API test, but conf-sanity
300 drives it end to end through `lfind --device` — the predicates, the
plain-argument form, `--device=VALUE`, the two-targets refusal. What was
missing were the three selectors above, which are now there.

**Unrun.** None of the four needs anything exotic, but this host has no Lustre
mount, so only the lifted `test14` has actually executed. 157c, 157d and
conf-sanity 300 are owed a lab.

## The trim moves into llapi_find_with_cb() — two copies, not three (2026-09-08)

Third of the open lreview findings. The reviewer asked for the trailing-slash
trim to move into `llapi_find_with_cb()` and for "the three other copies" to
go. Half right, and the half that is wrong is worth writing down: **the four
loops are the same shape doing three different jobs.**

| | what it trims | why |
|---|---|---|
| `llapi_find()` | the walk's start point | `lfsr_name` points into the walked path |
| `llapi_scan_namespace()` | the walk's start point | the same reason, its own copy since 68094 |
| `llapi_scan_fid()` | `mnt_path` | a mount it then *composes* a name onto |
| `llapi_find_since()` | the caller's spelling | a prefix it then *composes* names onto |

Only the first two are about traversal, and only they funnel through
`llapi_find_with_cb()`. The other two have no walk at all: a trailing slash
there doubles a separator rather than hiding a basename, and folding them in
would be a shape match, not a common cause — exactly the sort of tidy that
reads well and breaks something a round later.

So: the trim is now in `llapi_find_with_cb()`, the one way into the
traversal. `llapi_find()` is a straight tail call again, `llapi_scan_namespace()`
keeps only the copy its own `const char *` signature forces, and an external
caller of the exported walk gets the fix without asking for it. The `--threads`
path gets it too, which it did not have from the scanner side before.

Verified off Lustre: `-name` matches a trailing-slash start point, no doubled
separator below it, `/` keeps its slash, the threaded arm agrees with the
serial one, and an over-long path still names itself before `-ENAMETOOLONG`.

## llapi_scan_fid() reads through mnt_fd, not through the composed path (2026-09-08)

The second of the open lreview findings, and the user's call again.
`llapi_scan_fid()` resolved the FID through `mnt_fd` and then read the object
through `mnt_path + "/" + rel` on `AT_FDCWD`, so **one argument decided which
filesystem was resolved and the other decided which was read**. The statx, the
object's open and the parent's open all go through `mnt_fd` now, at the name
`fid2path` answered.

**What it buys.** An fd pins its mount; a path string is resolved afresh every
time. A mount replaced between `llapi_root_path_open()` and the scan had the
resolve read one filesystem and the gather another — rc 0, a complete record,
nothing said. It also takes the mount prefix off every lookup, three per
object, which over a changelog's worth of FIDs is what this entry point is
for.

**What it does not buy.** `mnt_path` is still required and still what
`lfsr_path` is built from, so a wrong one still *mislabels* the answer. It
just no longer decides what was *read*. The header and the page now say
`mnt_fd` is the filesystem, `mnt_path` is the spelling.

**The tightening, taken deliberately.** `llapi_fid2path_at()` uses `mnt_fd`
only as an ioctl handle — `OBD_IOC_FID2PATH` on the superblock — so any
descriptor in the filesystem worked. As a resolution base it has to be the
mount root. `llapi_scan_fid.3` already named `llapi_root_path_open(3)`, which
returns the root, and no caller in tree passes anything else; one that did
answered before and answers `-ENOENT` now. Loud, not silent.

**Three cases the absolute form did not have**, each a place to get it wrong:
the mount root (`fid2path` says `/`, which strips to nothing → `"."`), an
object directly under the mount (its parent *is* `mnt_fd`), and the in-place
`rel` split that finds a nested object's parent without a second `PATH_MAX`
buffer. None can be exercised without Lustre, so they are lifted into
`tests/lift/at_mntfd.c` and run both ways over a plain tree: six cases, same
`st_ino` each time, and `rel` unmodified after the split.

## find_prefilter() answers a bool; find_decide() answers 0 or an errno (2026-09-08)

The user's call, on the one lreview finding I had left open: three
neighbouring functions used `1` for three different things — *reject* out of
`find_prefilter()`, *matched and printed* out of `find_decide()`, *do not
descend* out of `cb_find_init()` — and the middle one lands in the same `ret`
the last one returns.

The user asked whether `find_prefilter()` should return a **negative** for
reject. Argued against and they agreed with the alternative: negative already
means *errno* everywhere in the file and in the library, so a negative that
means "rejected, normally" would be the first place `if (rc < 0) return rc;`
— the reflex at every call site here — turns a rejection into an error out of
a public API. It also does not fit `find_device_prefilter()`, which needs
three states.

**What landed instead.**

- `find_prefilter()` returns `bool`. It cannot fail — `fnmatch()` and a mode
  test, no allocation, no I/O — so there is no errno to return and no way to
  mistake its answer for one. Done in `LU-20605 llapi: build find on the scan
  record`, the commit that adds it.
- `find_decide()` returns `0` or a negative errno. The old fall-through `1`
  for *matched* was read by none of its four callers — printing is the answer
  — and it was the value that landed in `cb_find_init()`'s `ret`, safe only
  because the `decided:` label overwrote it first. Done in `LU-20611 llapi:
  split cb_find_init's decider out`.
- The crossings tidied where the two conventions meet:
  `find_device_prefilter()` spells its `1`/`2` explicitly, and the `== 0`
  call sites became `!`.

`find_device_prefilter()` keeps `int` and its `{0, 1, 2}`: three answers need
one, and its `1` agrees with the bool's `true`.

Both commit messages now state the contract. All 20 commits build, the header
compiles, checkpatch gains nothing; `-maxdepth 1` — the one live user of the
*do not descend* `1` — still stops where it should.

## lreview over the whole stack: 70 findings, three commits that did not build (2026-09-08)

Ran `lreview` on commits 5 through 20 in turn, fixing each before moving on —
70 findings, on top of the eight on the folded 68094 earlier the same day.
The ones that mattered:

**Three commits did not compile.**

- **68156** (`LU-20606`, ldiskfs backend): `llapi_scan_device_test.c` used
  `big` and `search`, both declared thirteen commits later. The union is now
  declared here; `.lfsp_search` stays with the ZFS commit that introduces
  `search`.
- **68288-and-after** (`LU-20637`, name a device scan's objects): adding
  `lfsp_fsname` ate the `/*` that opened `lfsp_got`'s comment, so **the
  installed public header did not compile** from that commit until the
  LU-20650 rewrite repaired it by accident.
- **`--since`** (`LU-20650`): `st->fss_undecided` with no such member — mine,
  from the layout fix below landing in a commit whose struct gains the field
  one commit later.

A sweep now builds `lustre/utils`, compiles `#include <lustre/lustreapi.h>`
and syntax-checks the three test programs **at every one of the 20 commits**.
All green. This class of defect has appeared in three separate rounds now;
the sweep is the answer to it.

**Six real defects in the code.**

| Where | What |
|---|---|
| `liblustreapi_pfind.c` | An object whose layout could not be **read** was merged with one that has **no** layout and answered off a forged filesystem default — the outcome `find_lmm_fits()` accepts a short foreign EA to avoid, reached the other way round. Reachable for a torn composite EA and a byte-swapped `LOV_MAGIC_SEL`. `find_rec_layout()` now forges a default only for the no-layout case; the other is counted undecided. |
| `liblustreapi_pfind.c` | `--ost` was missing from `find_changelog_needs_lookup()`, so `--changelog --resolve --ost` silently lost every object unlinked since its event — the case `--changelog` exists for — and cleared `fp_got_uuids` each time, re-looking-up the OSTs for the next object that did resolve. |
| `libscan_zfs.c` | The ZFS backend declared `LLAPI_SCAN_SO_GEN`, so the core built an **IGIF from the low 32 bits of a dnode id** for every object with no LMA, against `llapi_scan_device.3` and the core's own comment. Two dnodes 2^32 apart with the same generation collide. `osd-zfs` creates `O`, `O/<seq>`, `d*` and `oi.N` with no LMA, and `--internal` delivers them. |
| `liblustreapi_scan_changelog.c` | A `CL_MARK` was handed `lfsr_fid` = the mark's flag bitmask with `LLAPI_SCAN_FID` set: `cr_markerflags` shares the union with `cr_tfid`, and `CLM_ON\|CLM_START` is inside `FID_SEQ_IGIF`. With `_RESOLVE` the consumer opens by it. |
| `lustreapi_internal.h` | `scan_param_whole()`'s `ends[]` had a stray second `lfsp_stats` **after** `lfsp_search`; the loop keeps the *last* entry that fits, so `lfsp_size == 56` copied 48 bytes and dropped `lfsp_search` — a ZFS pool on file vdevs then goes unfound. LU-20637 was silently repairing it later. |
| `liblustreapi_scan_batch.c` | `scan_param_copyin()` is shallow, and `lfsp_got`/`lfsp_stats` are pointers the scan writes through — on its own thread, after `llapi_scan_namespace_open()` has returned, into whatever frame the caller's block lived in. The tree's own idiom is a stack-local stats block. The batch layer now drops both. |

Plus `llapi_scan_fid()` answering `-EINVAL` for a negative `mnt_fd`, where
`-EINVAL` also means *this FID has no name*: a consumer looping over a
changelog with an unopened mount counted every object nameless and exited 0.
`-EBADF` now, as `llapi_scan_rec_path()` already answers.

**The device scanner never filled `lfsp_got`.** Same fold artefact as 68094's:
the `known` block lived thirteen commits downstream of the entry point that
documents it. Moved to LU-20606, narrowed to the bits that exist there and
widened again in LU-20637, where `LLAPI_SCAN_OWNER` and `LLAPI_SCAN_LMV_SHARD`
arrive.

**Man pages.** `-k, --skip` lost its `.TP` twice over and rendered as running
text; `--since-cookie` was documented twice, thirty identical lines; `--ost`
and the object times were listed as always refused when they are refused only
without `--resolve`, in `lfs-find.1`, `llapi_find_since.3` and the commit
messages alike.

**Open, for the user**

- Return-convention refactor: `find_decide()` returns 1 for *matched* where
  `find_prefilter()` returns 1 for *reject*. Safe today only because
  `cb_find_init()` resets `ret`.
- `llapi_scan_fid()` resolves through `mnt_path` but opens through `AT_FDCWD`;
  the reviewer suggests `statx(mnt_fd, rel, ...)` so the two cannot name
  different filesystems.
- Put the trailing-slash trim in `llapi_find_with_cb()`, where every caller
  funnels through, and drop the three other copies.
- Tests: `llapi_find_device()`, `llapi_scan_fid()` and
  `llapi_scan_changelog_test` have no suite entry; `lfind`'s `--local`,
  `--target` and `--internal` are uncovered; and the `-EBUSY` batch test never
  has the first consumer inside `llapi_scan_next()`, so the case that
  reproduced the ASan overflow cannot fail.
- Whether `test16` (which exercises `lfsp_got` on the callback API) should
  move to the change that adds `lfsp_got`.

**Declined, with reasons recorded**: the append-only objection to
`lfsp_search`'s position (nothing has shipped; the struct is new in this
series), the forward references to `--since`/`--changelog` from the commit
that precedes them, and a `CLIENT_VERSION` gate on 160aa-160ad — adilger's own
reply on `2a3ed73d` settles that one.

Nothing is pushed. checkpatch is clean of anything but the known noise on all
20; `lfs find` smoke-tests pass off Lustre, and `-printf %LP` prints `0` for a
file with no project id, which is the claim the commit message got wrong.
**Lab verification is still owed** — this host has no Lustre mount, so
`llapi_scan_test`, `llapi_scan_device_test`, conf-sanity 300 and sanity
56El/157c/160aa-160ad have not been run against the fixed tree.

## The record's lifetimes are documented per field (2026-09-08)

From the user's question, not from a review comment.
`llapi_scan_namespace(3)` said only "valid only for the duration of the
callback"; it now has a **Lifetimes** subsection saying when each part stops
being the object's, because the answers differ and two are shorter than that
rule reads:

- `sr_name` points **into** `sr_path`, not beside it.
- A directory's `sr_path` is rewritten by **its own descent**, before any
  callback below it runs — it does not last until its next sibling.
- `sr_fd` for anything but a directory is closed **the moment the callback
  returns**; a kept copy names a descriptor whose number is about to be
  reused.
- `sr_lmm`/`sr_lmv` last **longer** than the rule — until the next object's
  gather — which is the more dangerous half. The record is honest within the
  callback (no layout leaves `sr_lmm` NULL), but a kept pointer describes
  whichever object was gathered most recently, and the gather clears the
  magic without clearing the body.
- The record itself is a stack local of the traversal callback, so even the
  by-value fields need the struct copied.

`llapi_scan_next(3)` is named as the exception for a consumer that needs a
record to outlive delivery, and **its own page gained the two things the
implementation shows and the prose did not**: the batch is released at the
**top** of the following `llapi_scan_next()`, before that call waits for the
scan rather than when it returns — so handing a batch to a worker thread and
calling again to overlap the next fill releases what the worker is reading,
and the `-EBUSY` that refuses a second *caller* does not refuse a *reader*
racing one. And the arena is **rewound, not freed**, so such a reader finds
the following batch's bytes rather than a fault. What that page already had
was right: everything is deep-copied, and `lfsr_parent_fd`/`lfsr_fd` are −1
because a batch cannot carry a descriptor the callback closed.

**Split across two commits:** the section into 68094, the batch sentence into
`llapi_scan_next`'s own commit, since the function does not exist at 68094.
Checked that the cross-reference never precedes the page it names, and that
no commit mixes `sr_` with `lfsr_` — this one needed **three** passes to get
right, a second hunk having applied cleanly with the new spelling while the
first conflicted.

## DONE: renumbered 165-168 to 300-303 (2026-09-08)

**adilger `5bcbf4dd`, 68156 ps16, same file and line as the AI's
`a9942381`:** *"This test number is also being used in at least one other
patch. It would be better to put this up at 300 or 400 to avoid contention
(here and in the future)."*

**So the decline posted at 15:38 is wrong and must be reversed.** It rested
on "the collision it guards against hasn't happened" — the maintainer says it
has, and said so on ps16, three days before the AI restated it. Both the
maintainer and the AI have now asked for 300/400.

**How the error happened, because it is the second time today:** the ten
adilger threads on 68156 were listed this morning and classified as "a
separate pile", then never read. The AI's `a9942381` and `4d552522` were both
*restatements* of adilger comments sitting at the same lines, and both were
answered without reading the originals. A restatement is not the comment.

**All three done.** Renumbered to **300-303** across the whole stack with one
scripted `rebase --exec` pass, `a9942381` corrected, `5bcbf4dd` answered.

**The substitution had to be anchored in the tree and could be bare in the
messages**, and knowing which is the whole job: `conf-sanity.sh` holds 14
addresses containing `192.168.`, so a bare `\b168\b` would have rewritten
them. Every message reference was enumerated first — sixteen lines, all ours
— so bare was safe there. Checked after: 14 IPs before and 14 after, and the
`EXCEPT_SLOW` duration comment (`# 8 22 40 165 (min)`) untouched.

**A second pass was needed for `test_16N` in the messages:** `_` is a word
character, so `\b166\b` never matched inside `test_166`. Caught by sweeping
every commit rather than trusting the first pass.

**Verified, not assumed:** `PASS 300 (45s)` on the lab, with
`scan_osd_ldiskfs.so` installed — so the renumber and the plugin rename are
both confirmed by a run, not by reading the diff. `Test-Parameters` now says
`ONLY=300`.

## 68617 gains a Fixes: tag (2026-09-08)

arshad512 `c741cc44`, the last unresolved thread on 68617 and the only one
from that reviewer: *"Should the be also in 'Fixes:' section?"*, anchored on
the line citing `c5050e412572`.

**Answerable without asking him.** That commit is cited as *evidence* — it is
what lands v0.9.1, proving there is a commit version to name — not as the
cause. The commit that wrote the wording is **`155cf6d41dac ("LU-4315 doc:
updating ls-tu man page style")`**, which added the `.\" Added in release
0.9.1` line; `9a14d75e0a` only moved the file. The tree carries 1699 `Fixes:`
lines, so the tag is in keeping. Added before `Signed-off-by`, as the tree
places it.

**And a habit corrected.** Checkpatching `git show` output — which is what I
did all day — indents the message four spaces and yields three phantom
warnings per commit, including one telling me the `Fixes:` line was
misformatted *while quoting it back verbatim*. Through
`git format-patch -1 --stdout` the same commit is **0 errors, 0 warnings**.
Much of today's "known noise" was this.

## stack_trap loses its EXIT and its justification (2026-09-08)

adilger `f51bb905`, two style points, both right. `stack_trap`'s second
argument defaults to EXIT (`test-framework.sh:7459`,
`sigspec="${2:-EXIT}"`), and a `setupall` trap after `stopall` is the
ordinary shape.

**The number that makes it more than taste:** the base tree passes an
explicit EXIT **18 times of 92**. This series had added **13 more**, taking
the file to 31 of 106 — we were the main source of a minority style.
Dropping ours leaves exactly the 18 that were already there, and the diff
against the base is insertions only, so none of upstream's were touched.
Five more in `sanity.sh` went the same way.

Applied per commit with a `rebase --exec` pass, since the calls span several
changes; scoped to lines this series added rather than a blanket sed.

**Verified:** `conf-sanity 300` PASS, and the log shows the client restarting
after the test body — the `setupall` trap firing, which is the thing a
mangled trap would break. `sanity` 56El, 160aa–160ad PASS.

**157c failed first, and it was the fourth stale artefact of the day.**
`make` in `lustre/utils` does not rebuild `lustre/tests`, so
`llapi_scan_test` still expected the record's old `sizeof` from before
`lfsr_gen` was removed, and reported *"6 records did not carry sizeof(struct
llapi_scan_rec)"* — which reads exactly like a real defect. Rebuilt: PASS,
17 subtests. Worth naming that this was also the **first** run of the
namespace test since the IGIF change; the earlier 7/7 was
`llapi_scan_device_test` alone.

## The struct comments stop enumerating scanner capabilities (2026-09-08)

adilger `462553a5` and `611473dd`, one fix — and the first is sharper than it
reads. It is anchored on `lustreapi.h:763`, *"It offers no path and no name"*,
so he is **disputing that sentence**, not volunteering a fact: an OST object
keeps its MDT parent FID in `trusted.fid`, from which a pathname can be made.

**Our own series falsifies it two patches later.** LU-20637 (68288) reads
exactly that xattr as `lfsr_owner_fid` / `LLAPI_SCAN_OWNER` and names OST
objects from it while the OST is down. So the comment went stale **inside its
own series** — which is `611473dd`'s complaint demonstrated rather than
predicted.

Both blocks trimmed to the part that does not change: the filter sees only
what the scan already had, and 0 means a default the two scanners do not
share. The field-by-field lists go. **Nothing was lost** — both man pages
already carried the filter-time contract verbatim, and
`llapi_scan_namespace.3` already carried its own default in full, so the
header was duplicating them. `llapi_scan_device.3` gains the one sentence it
never had: what 0 means there.

**An earlier read of mine was wrong and is corrected here:** I first took
`462553a5` as "he is telling us something we already do, resolve it". It is a
correction to a claim in the comment, and the fix is a trim, not a citation.
Reading the anchor line is what changed the answer.

## Both scanners fill the stats, and the struct says it is extensible (2026-09-08)

adilger `5aae920f` and `15a0778a`, answered together — same struct, same
complaint.

**`5aae920f` — "make this extensible" was already true and written down
nowhere.** `ss_size` negotiates exactly as `lfsp_size` does: the library
writes back `min(ss_size, sizeof)` with `LLAPI_SCAN_STATS_MIN_SIZE` as the
floor, so counters appended later leave an older caller reading its own
fields. `llapi_scan_device.3` now says so.

**Deferred, with the reason:** the aggregates he wants (total size/blocks,
histograms, per-UID/GID/PRJID) and the **stats mask** to select them are one
patch and want building together. Totals change what a *namespace* scan must
read per object — a device scan has size and blocks in hand, a walk fetches
them only when asked — so the mask is what makes them affordable, and a mask
with nothing behind it is a promise.

**`15a0778a` — the namespace scanner now fills stats too.** His prediction
about staleness was already true: the comment said "the namespace scanner
does not use it" while the **changelog scanner already did**
(`liblustreapi_scan_changelog.c:1134`). The struct comment now describes the
field and names no scanner.

**Why the walk never filled it, which is the honest answer:**
`struct llapi_scan_stats` and `lfsp_stats` are introduced by **68156**, not
68094 — the field arrived with the code that needed it. So the fix lands in
68156 as well; it cannot go in 68094, where the struct does not exist.

Counted atomically, `llapi_scan_namespace()` running its callback on every
thread at once where the device scan merges per-worker counters at the end.
**Measured:** 201 objects exact at 1, 4 and 8 threads;
`seen == filtered + skipped + sum(class)` holds in every arm; a filter
rejecting every third gives 7 seen / 5 emitted / 2 filtered.
`tests/lab-r18/ns_stats.c`.

**One stale cross-reference this created and caught:** the `lfsp_search`
paragraph said it was "the same case" as `lfsp_stats` — unread by a walk.
Stats are now read by both, so that sentence was wrong the moment this
landed. Fixed in 68163.

## A no-LMA object is answered with its IGIF (2026-09-08)

adilger `e3aae0e0`, third part: *"the right place to return
inode/generation would be as an IGIF FID"*. Right, and the tree agrees —
`osd_scrub.c:632` and `:2612` build exactly that for an inode with no LMA. We
were handing out the parts and telling the consumer to assemble them, and
**nothing consumed `lfsr_gen`**: across utils, tests, headers and man pages it
was only ever produced.

So `lfsr_fid` now carries the IGIF and `LLAPI_SCAN_FID` is set;
`lfsr_gen`/`LLAPI_SCAN_GEN` are gone — which also deletes the field whose
appending parts 1 and 2 of the same comment objected to, so one change answers
all three. `lfsr_ino` stays: every object has it, and a ZFS object id is wider
than an IGIF holds. `LLAPI_SCAN_GEN`'s bit is left unused rather than
renumbering the ones above it.

**The man page had claimed the opposite** — *"One is not invented for it here
— reconstructing a FID is LFSCK's job"* — and now says an IGIF is not a
reconstruction but the FID such an inode has.

**Measured on a real no-LMA inode**, created straight on the ldiskfs side so
it has no `trusted.lma`: unfixed prints `obj:159` with 3 objects named by id
alone; fixed prints `[0x9f:0xdd8ab9ce:0x0]` and none.
`llapi_scan_device_test` 7/7.

**Three build traps in one item, all the same shape — a stale artefact
answering.** conf-sanity 300 reformatted `/tmp/lustre-mdt1`, the scan fixture,
so the unit test failed on an emptied device and looked like a regression;
the untouched image scanning fine is what separated the two. Then a
reverse-apply of one file left `lfsr_gen` used but undeclared, and
`make >/dev/null 2>&1` hid the compile error, so a **stale .so answered the
comparison and showed no difference**. Every arm since is timestamp-checked
before it is believed.

## The scan plugin is named scan_osd_ldiskfs.so (2026-09-08)

adilger `bd5ac2cf` on 68156's COMMIT_MSG: *"it would be useful to name this
consistently, like scan_osd_ldiskfs.so"*. Right, and it was our own stated
precedent that we failed to follow — the loader's comment says "plugins
beside mount_osd_ldiskfs.so, found the same way", and `mount_utils.c:511`
loads `mount_osd_FSTYPE.so`, while ours dropped the `osd_`.

Renamed in the loader, `Makefile.am` and `lustre.spec.in`; the `name` strings
stay "ldiskfs"/"zfs" so the ENOTSUP message still reads properly, with the
prefix in the path format. Split by backend: the ldiskfs half and the loader
into 68156, the ZFS half into 68163 — and 68156's loader is **single-backend**
(the `scan_backend_name[]` array arrives with 68163), so the two commits carry
different shapes of the same rename.

Verified per commit: `scan_osd_zfs.so` appears only from 68163, no
un-prefixed name survives anywhere, and the renamed plugin genuinely loads —
installed copy moved aside, no installed `scan_osd_ldiskfs.so` to fall back
on — scanning 8 directories with `--links 2` still answering 3.

## fid_is_root() moved to the UAPI header (2026-09-08)

**adilger's `3459fec3` on 68156 ps16 (5 Sep) was never answered** — the AI's
`4d552522` was restating it, and replying to the restatement is not replying
to him. He asked why `fid_is_root()` is not usable here and said the inline
can be moved to the UAPI header, or split into a `lustre_fid_server.h`.

**My reply to the AI earlier today was bad reasoning and has been overtaken.**
It gave as the objection that the move would mean deleting the server-side
definition — which *is* the move, not a blocker, and he had already said so.

Done properly: `LU_ROOT_FID` (`uapi/.../lustre_fid.h:30`) and `lu_fid_eq()`
(`:363`) are both already public, so the helper is a one-liner over things
userspace has. It now lives in the UAPI header **without `unlikely()`**, that
header being compiled in userspace, and is gone from
`lustre/include/lustre_fid.h`, which includes the UAPI one — so llite, lmv,
lod, mdd and mdt are untouched. `scan_classify()` calls it instead of
open-coding `lu_fid_eq()` against `LU_ROOT_FID`.

**Built the kernel side, not just userspace:** llite, mdt, lod, mdd and lmv
all recompiled and relinked clean, which is the check a shared-header move
needs. `tests/lift/root_fid.c` still 4/4.

Reply posted by the user on `3459fec3`, left unresolved for him to close.

**Loose end:** the AI's `4d552522` is resolved carrying the superseded claim
that the move could not be made.

## Replies posted for the sixteen (2026-09-08)

Six `gerrit review --json` calls, one per (change, patchset), targeting the
patchset each comment was written on: 68156 ps17 (3), 68157 ps17 (4), 68158
ps17 (3), 68159 ps17 (2), 68160 ps18 (1), 68163 ps16 (3). Read back
afterwards — a thread's state is its **last** comment's flag, so counting the
AI's own says nothing.

**Fifteen resolved, one left open on purpose:** 68158 `46c9be5f`, the only
pure decline, so the reviewer can push back on it. The other two declines
(68157 `0a865f6a`, 68156 `7e92da87`) each came with a change and are resolved
with the reason stated.

Every reply says **"Lands in the next patchset."** — nothing is pushed, so
`Done.` would have been a false claim. The cover message says so outright.

**Not replied to:** 68156 `a9942381`, the renumbering skipped for the user.
Answering it would be answering for a decision not made.

AI threads still unresolved: **six** — that one plus the five older
deliberate ones (68095 `937bc492`, 68156 `ab78d3de`, 68159 `e6fb45c4`,
68417 `122b863e`, 68420 `39df2275`).

## The 17 AI comments: 16 closed, 1 skipped (2026-09-08)

**Worked through in one pass.** Six were real defects, four of them
user-visible: a foreign directory dropped by `--links`, a torn linkea reported
as a non-match, an LMV buffer leaking the previous object's bytes, a chunk
boundary double-counting, `lfind` printing every option error twice, and
`lfs> find` searching the word "find". Three were declined with reasons on the
evidence (the `-ENOTSUP` sentinel, the depth check's second copy, making the
two scanners' LMV sizes agree). The rest were comments, man pages and commit
messages that said something untrue.

**Two findings came out of the work rather than the queue:**
`EXT2_SF_WARN_GARBAGE_INODES` is never set, so `EXT2_ET_INODE_IS_GARBAGE` is
unreachable as shipped — open for the user, below. And `-printf %Lc` prints a
foreign directory's `lfm_length` as a stripe count, upstream and unfixed.

Every fix is folded into its own change with a message paragraph, checkpatch
is clean over all 21 commits, the whole stack builds, and the day's diff
builds and runs on the lab. **All unpushed.**

## The AI backlog was NOT empty: 17 untriaged (2026-09-08)

The 2026-09-06 evening round left 14 unlooked-at, and **68163 carries three
more that predate it** (ps16) and were missed by every sweep since. Current
count from the REST API: 40 unresolved threads, of which 17 are AI comments
with no reply, 5 are AI threads deliberately open with a reply on them, 17
are adilger's and 1 is arshad512's.

Untriaged: 68156 `a9942381` `4d552522` `7e92da87` `edaaad1a`, 68157
`1e2c193e` `7280c834` `0f09897a` `0a865f6a`, 68158 `46c9be5f` `25ba086d`
`8516da85`, 68159 `ccbe7b56` `0aaa4e59`, 68160 `824b9aa9`, 68163 `a93f237a`
`87ba1222` `de2957d5`.

**Done: 68159 `ccbe7b56` and `0aaa4e59`, 68156 `7e92da87` and `edaaad1a`,
68157 all four, 68160 `824b9aa9`, 68156 `4d552522`, 68158's three, 68163's
three** — see below. **Seventeen triaged, sixteen closed; one skipped for
the user:** 68156 `a9942381`.

## 68163's three, unlooked-at since ps16 (2026-09-08)

The three that predate the evening round and that every sweep missed. All
real. `87ba1222`: two `-EINVAL` entries in ERRORS, the pool case folded into
the argument-check entry so there is one per errno. `de2957d5`: `sp_search`
was on neither page — `llapi_scan_device(3)` sends readers to
`llapi_scan_namespace(3)` for the structure and that page's field walk left
it out; `sp_stats` was already the model for how to say it. `a93f237a`: four
paragraphs of the commit message justified the patch against an earlier
revision of itself, which a reader from `git log` cannot see; rewritten to
state the leading-slash rule once and its consequences.
`docs/rounds/round22/68163-three.md`.

## `lfs> find` searched the word "find" (2026-09-08)

68158's three. The middle one, `25ba086d`, is a **reachable user-visible
bug**, not the contract note it was offered as: `execute_line()`
(`parser.c:384`) sets `optind = 0` for the interactive shell, `prev_optind`
seeded from that, and `lfs> find /tmp -maxdepth 0` answered
`failed for 'find': No such file or directory` before printing `/tmp`. It
searched `argv[0]`. Verbatim upstream (`5afbab284e:lfs.c:7256`), but our
patch documents a contract untrue of an in-tree caller. Fixed with
`optind ? optind : 1` — not a guess: glibc reads 0 as "reinitialise" and
scans from `argv[1]` anyway.

`8516da85`: added `lfs_find_parse_init()` beside the `fini()` already owed,
and switched both front ends to it. `lfind`'s copy of the initialiser was
**already one field short** — three of the four named, `fp_min_depth` left
implicit.

**`46c9be5f` declined on evidence:** `lfind` calls `llapi_find_device()` and
never walks, so `--mindepth`/`--maxdepth` are refused outright and the
predicted second copy of the range check never has to be written. Moving it
would make `lfind` complain that 3 > 1 for options it does not support,
ahead of the message that says so. `docs/rounds/round22/68158-three.md`.

## The root test ignored f_ver (2026-09-08)

68156 `4d552522`, and both of its points hold. `fid_is_namespace_visible()`
reaches the root through `fid_is_root()` = `lu_fid_eq()` against
`LU_ROOT_FID`, and `lu_fid_eq()` is a **whole-struct memcmp**; our
`fid_seq_is_root(seq) && f_oid == FID_OID_ROOT` ignored `f_ver`, so a root
FID with a non-zero `f_ver` was called namespace-visible where the MDT would
not. `scan_decode_lma()` swaps and stores `f_ver` off a live device, so it is
not structurally zero.

**Declined the suggested mechanism** — moving `fid_is_root()` into the UAPI
header, which would collide, `lustre/include/lustre_fid.h:133` including it,
so the server-side definition would have to go in the same patch. **Done
instead:** `lu_fid_eq(&lma->lma_self_fid, &LU_ROOT_FID)`, both pieces already
public, exact rather than approximate.

`tests/lift/root_fid.c`: **3 pass / 1 fail → 4 / 0**, with the echo-client
root — the case the spelled-out test existed for — unchanged. Byte-identical
answer on a healthy MDT. `docs/rounds/round22/4d552522-root-fid.md`.

## lfind printed every option error twice (2026-09-08)

68160 `824b9aa9`. `lfs_find_parse()` prints its own diagnostic and documents
that the caller must set `opterr = 0`; `lfs.c:15867` does, `lfind`'s `main()`
did not, so glibc's default of 1 printed a second one. Reproduced, fixed,
reproduced fixed — once each for `--bogus` and a short `-Q`, and a good run
still answers. The contract's other half needed nothing:
`lfind_parse_target()` compares strings rather than calling `getopt()`, so
`optind` is still 1 when the parser is reached, and setting `opterr` ahead of
it suppresses no diagnostic of its own.
`docs/rounds/round22/824b9aa9-opterr.md`.

## 68157's four, all on one comment (2026-09-08)

`0a865f6a`, `7280c834`, `0f09897a` sit on the same block above
`find_get_projid()`; `1e2c193e` is its commit message.

**`0a865f6a`: the code is right, the comment was wrong.** `ENOTSUP` and
`EOPNOTSUPP` really are one number, and `get_projid()` really does pass back
`-errno` unconstrained — but the sentinel is returned *before* `get_projid()`
is reached and only when `fc_path == NULL`, which is the same condition
`find_decide()` decodes it under. An `-ENOTSUP` from the ioctl keeps a path
and is reported as the error it is. `fc_path != NULL` with `fc_fdp == NULL`
is unreachable — every site sets the two together. **Declined the code
change**; fixed the comment, which named the *value* as the discriminator and
would have led a reader to drop the guard as redundant.

The other three: the stranded one-liner folded in, the "at this patch /
arrives with LU-20611" schedule dropped (it pointed at this patch's own
ticket for a caller it does not contain), and the message now names
`struct find_ctx` and `find_get_projid()`.
`docs/rounds/round22/68157-projid-comment.md`.

**The rebase went wrong twice and the tree-hash check caught it.**
`git log --grep` matched my own `fixup!` commit and the `edit` landed there;
then resolving a later commit's conflict by taking the incoming side — right
for the `find_respell()` it carried — **re-added the one-liner I had just
deleted**, so the tip held the comment twice and still built clean. Nothing
but comparing the finished tree against the pre-fold tree would have found
it. Sweep every commit, not just the tip.

## DECLINED: renumbering conf-sanity 165-168 (2026-09-08)

68156 `a9942381`, the only one of the seventeen not closed. The AI asks for a
large round number with gaps — test_300 or test_400 — so two patches adding to
this suite in parallel do not both take the next free small number.

**The premise is exactly right.** Upstream's base stops at `test_164` and then
jumps to `200a`, so 165-168 are precisely "the next four free". 300 and 400 are
both clear (200a-e, 250, 802a are the neighbours).

**Declined on the practice, and the reply is posted and resolved.** Every
conf-sanity test added upstream in the last eighteen months took the next
free number (156, 157a, 160-162, 164) or a suffixed variant of a related one
(73c-f, 82c, 28b, 88a, 123aj) — **not one jumped to a large round number**,
so 300/400 is a preference rather than this suite's convention. A parallel
patch taking 165 conflicts *textually* in `conf-sanity.sh` when the second
rebases, so the collision is detected and costs one renumber if it happens,
rather than certainly now. And `test_167` carries the CI history the Janitor
−1 on 68288 is being chased through.

**A claim of mine that was wrong, corrected here:** 165-168 do *not* sit
beside related tests. conf-sanity 160-164 are MGS/nid/registration tests; the
`lfs find` tests are in `sanity.sh`. There is no grouping argument for
keeping the numbers, and the case rests on the practice evidence alone.

**The cost, had it gone the other way:** The cost is a sweep of 25
references in the tree, 7 in the series' commit messages and Test-Parameters
(`ONLY=165`), the LU-20637 Jira thread on test_167, this board, the round
records, and ten memory files — plus the shorthand "conf-sanity 165/166/168"
that has been the working vocabulary for weeks. Renaming that is your call,
not a style fix to apply quietly.

Resolved rather than left open, unlike 68158 `46c9be5f`: this is a style
preference contradicted by the history and had been raised twice with no
answer, where `46c9be5f` is a design point that new information could
reasonably change.

## OPEN FOR THE USER: the garbage-inode flag is never set (2026-09-08)

Found while building a fixture for 68156 `edaaad1a`. `scan_ldiskfs_chunk()`
catches `EXT2_ET_INODE_IS_GARBAGE` and its comment says a body "libext2fs
calls garbage" is skipped — but `check_inode_block_sanity()` returns
immediately unless `EXT2_SF_WARN_GARBAGE_INODES` is set, and
`libscan_ldiskfs.c:271` sets only `EXT2_SF_SKIP_MISSING_ITABLE`. **Proved with
a standalone probe: flag off, libext2fs refuses nothing; flag on, it refuses
exactly the four corrupted inodes.** So that arm is unreachable today and a
garbage inode is parsed as an object.

**Not decided, deliberately.** Setting the flag makes the code do what it
says, but `check_inode_block_sanity()` verifies a checksum and an extent
header for *every inode read*, on the hot path of a scanner measured in
millions of objects a second. A throughput question, wanting its own
measurement.

## An unreadable inode at a chunk boundary counted twice (2026-09-08)

68156 `edaaad1a`. The skip arm `continue`d without asking `ino > end_ino`, so
an unreadable inode just past the bound was consumed by this chunk and read
again by the next; `ss_seen` and `ss_skipped` both took it twice. Checked
against libext2fs's own source first: `*ino` is assigned after all three of
those errors and before the return, unlike the earlier ones. A reserved inode
that could not be read was also counted as an object; now it is not.

**Measured on a real device** — a copy of the lab MDT with three of the four
inodes in the block at chunk 0's boundary (inode 75001, `end_ino` 75000)
overwritten: **unfixed 8 of 270 skipped, fixed 4 of 266.** Exactly double.
`docs/rounds/round22/edaaad1a-chunk-boundary.md`.

**A lab trap that invalidated three earlier readings:** the ldiskfs backend is
a **dlopened plugin**, not part of `liblustreapi.so`, and
`scan_backend_load()` tries `PLUGIN_DIR/scan_ldiskfs.so` *before*
`$LUSTRE/utils/`. So `make lfind` + `LD_LIBRARY_PATH` — enough for anything in
`liblustreapi` — silently ran the **installed** backend. To test a backend
change: `make libscan_ldiskfs.la`, move `/usr/lib64/lustre/scan_ldiskfs.so`
aside, set `LUSTRE=<tree>/lustre`, put it back after.

## The LMV buffer kept the last object's bytes (2026-09-08)

68156 `7e92da87`, both halves verified. `scan_lmv_to_user()` cleared only the
48-byte header of a worker's one reused 4096-byte buffer, so a directory's
shard area held whatever the last object left — **96 of 96 bytes, measured,
a preceding foreign directory's opaque value**. A consumer sizing
`lum_objects[]` by `lum_stripe_count` (as `lmv_dump_user_lmm()` does) reads
it; `rec->lfsr_lmv` points straight at that buffer. Fixed by clearing as far
as such a read can reach, bounded by the room. `sw_lmv` is now a union of the
two structures it holds, not a bare `char[]` the call site casts both ways.

**Declined:** reporting `lmv_user_md_size(count, SPECIFIC)` to make the two
scanners' sizes agree. A walk answers 144 with real shard FIDs, a device scan
48 with none — it cannot fill `lum_mds` without an FLD lookup. Agreeing on
144 would hand back zeroed FIDs as answers. Documented instead, in the record
comment and `llapi_scan_device.3`: `lum_objects[]` is measured by
`sr_lmvsize`, never by the count. `tests/lift/lmv_stale.c`, **3 pass / 1 fail
→ 4 / 0**. `docs/rounds/round22/7e92da87-lmv-size.md`.

**Two traps worth not repeating.** A non-raw Python string turned `\fI` into
a real form feed and the man page rendered `lmv_user_md_size(IcountR, ...)` —
caught by rendering the page, not by reading the diff; the tree is swept and
clean. And the fixup landing on 68156 **without** a conflict was the warning:
the `lfsr_` rename is a later commit, so the new comment named a field that
does not exist at that commit. Text now reads `sr_` there and `lfsr_` at the
tip, checked both ways.

## A torn linkea made the object a non-match (2026-09-08)

68159 `0aaa4e59`. `find_device_prefilter()`'s name loop broke out when an
entry could not be read and fell through to `return 1` — a rejection — where
the `nr == 0` case six lines above calls the same condition undecided. So an
object whose linkea claimed three names and spelled one was reported as a
non-match on a list nobody finished reading.

Reachable because `scan_linkea_entry()` caps `leh_reccount` by the *smallest*
entry that could fit, and entries are variable-length. Needs a genuinely torn
`trusted.link` — both backends deliver the whole xattr — which is the
condition `find_lmm_fits()` already exists for.

Fixed into the no-name branch's shape. **Checked and not a second defect:**
`nr == 1` with an unreadable entry 0 never reaches the loop, `scan_linkea()`
returning before it sets `LLAPI_SCAN_LINKEA`.

**Proved by lifting, not retyping** — `tests/lift/lift.py` cuts the three
static functions out of the real sources, so the unfixed arm is the shipped
text: **7 pass / 1 fail, then 8 / 0**. The first fixture was wrong (a short
first name caps `nr` to 1 and the loop never runs) and reported three
failures that were all fixture; the arms now assert the premise first.
`docs/rounds/round22/0aaa4e59-torn-linkea.md`.

**The rebase conflicted twice, usefully:** at 68159 the fields are still
`sr_`, and the `lfsr_` rename is a later commit, so the hunk was resolved
once in each spelling. Checked both directions afterwards.

## `--links` dropped a foreign directory on a device scan (2026-09-08)

68159 `ccbe7b56`, verified and **reproduced on a real device scan**.
`lmv_foreign_md.lfm_length` shares offset 4 with `lmv_user_md_v1
.lum_stripe_count`, so `find_decide()`'s nlink gate read a foreign LMV's
value length as a stripe count and asked for a stat. A walk pays one and
answers correctly; a scan has neither path nor descriptor, so the object went
undecided and was dropped **out of both `--links 2` and `! --links 2`** — the
same shape as round 22's `--projid 0` defect.

The gate is verbatim upstream (`5afbab284e:liblustreapi_pfind.c:2892`); what
this series adds is the caller with nothing to stat. Fixed with the
`lmv_is_foreign()` guard its three sibling arms already carry, folded into
68159 (`81c5db1519`) with the scripted-rebase method, tree hash unchanged.

Lab: `tests/lab-r18/09-arms-foreign-links.sh`, paired on one fixture —
**unfixed 3 pass / 2 fail, fixed 5 / 0**.
`docs/rounds/round22/ccbe7b56-foreign-nlink.md`.

**Noticed, not fixed:** `-printf %Lc` prints `lfm_length` as a stripe count
through the same aliasing. Upstream unchanged, a wrong number rather than a
dropped object — its own ticket, with the doubled-separator one.

## OWED: tell Artem the record layout moved (2026-09-07)

`struct llapi_scan_rec` now begins with `lstatx_t sr_stx` (offset 0), so it
casts to `struct statx *` and the Lustre fields follow past `0x100` —
adilger's `613572f2` on 68094, taken literally at the user's call.
`sr_size` moved from offset 0 to 256.

**PR 186 mirrors this struct by hand in Rust FFI.** Every field shifts, and
the failure is silent: during the lab run a consumer binary built against
the old layout read `seen 0xf8` where the value is `0xfdcf00000eff` — no
crash, no error, just wrong numbers. Two `static_assert`s (`offsetof == 0`,
`sizeof(lstatx_t) == 256`) protect anything compiled against our header; a
foreign-language binding gets nothing. Tell him before this lands, not
after.

Field order itself costs nothing: 100k objects, paired and alternating,
+0.02% full gather and −0.02% name-only (±0.31 ns/object).

## OWED in LU-20649: lfsr_event_time drops the nanoseconds (2026-09-07)

`liblustreapi_scan_changelog.c:615` does `co_time = r->cr_time >> 30`, so a
changelog record's event time keeps whole seconds and loses the low 30 bits
that hold the nanoseconds. Found while answering adilger's nanosecond
comment (`b3ce6f88`) on 68094, and **promised in the reply** — *"That is in
the changelog patch, LU-20649, and I will fix it there."*

**The thread is resolved**, so Gerrit will not remind us. It is the same
defect class he raised: a new interface that cannot carry the nanoseconds
another series is adding (66551, LU-1158). The object timestamps are fine —
`lfsr_stx` carries whole `struct statx_timestamp` — it is only the event
time that truncates.

## OWED upstream: a STATX_PROJID field (LU-12480, adilger's ask)

`e586539f` on 68094, 2026-09-04: push `STATX_PROJID` into the upstream
kernel so the scanner can drop its extra ioctl. Not a review finding and
nothing blocks on it — a piece of upstream work he suggested we take on.

Today `LLAPI_SCAN_PROJID` is one of the three fields gathered only when
named, because `get_projid()` opens the file when it has no descriptor. A
kernel that answered it would deliver it in the statx the MDT ioctl already
fills, and the per-object open disappears.

**The decision it will force:** `LLAPI_SCAN_PROJID` is a bit in this API's
own high half, while the low half aliases the kernel's `STATX_*`. A kernel
`STATX_PROJID` gives one field two names for the same number — unlike
`STATX_INO` vs `LLAPI_SCAN_INO`, which are two different numbers. Alias,
keep both, or deprecate ours; decide when the kernel side lands, and note
it touches `sr_projid` in the record too.

## 68288's Janitor −1 is NOT fixed, it is instrumented (2026-09-06)

`conf-sanity test_167` fails on **21 ZFS sessions** and passes on every
ldiskfs one. The 2026-09-03 `--search` fix **is** in PS11 and is not enough —
that "resolved" note was wrong. 165/166/168 all skip on ZFS, so 167 is the
scanner's only ZFS coverage in CI.

The blocker is that test_167 put `lfind`'s stdout and stderr in one file its
own `stack_trap` deletes, so **no CI artefact says why**. Fixed: stderr to
`$got.err`, quoted in the failure, as 166 and 168 already do. Built the lab
tree with `--enable-zfs` (2.2.11) and 167 **passes here**, so it is
environment-dependent — CI runs ZFS 2.3.2 on rocky8.10/9.6.
The test also now **asserts the export happened**: `export_zpool()` is an
`||` chain that leaves the pool imported and still answers 0 when anything of
it is in `/proc/mounts`, and a held pool is refused by the scan by design —
the leading hypothesis for the CI failure, and now its own error message.
`docs/rounds/round22/janitor-167-zfs.md`. No guess applied to the code.

## The directory pass stops opening the target twice (2026-09-06)

68288 `8d405103`, deferred on 2026-09-04 and now done. The map was a scan of
its own, so `--paths`/`--fid2path` opened the target twice — on ZFS an import
and an export each time — and on an OST the second open read one object and
threw the map away. It is now a **pre-pass on the same open**:
`scan_device_sweep()` lifted out of `scan_device_run()`, plus
`struct scan_prepass` and `scan_device_run_prepass()`, with
`scan_device_run()` kept as a wrapper so no earlier patch changes. The OST
refusal now comes from the target's label before either sweep runs, which is
the question the comment said we were not asking.

Measured: `--paths` now costs the same opens as a plain search (2 and 2, was
4). `llapi_scan_device_test` 7/7, `conf-sanity 165` PASS ×2.
`docs/rounds/round22/8d405103-prepass.md`.

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
