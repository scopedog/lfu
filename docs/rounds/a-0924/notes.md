# 2026-09-24: Artem's five comments on 68159 PS23 and 68163 PS23

Work tree `~/lfs-artem-0924`, branch `artem-0924`, from the round tip
`218cdea575` (backup: `backup/artem-0924-pre`). Do not use
`~/projects/lustre/lustre-scanfid` for sweeps: it is at `b1-tip` with
staged man-page work that `checkout -f` would lose.

## 68159: --projid is not a layout option -- FIXED, unpushed

`find_check_lmm_info()` includes `fp_check_projid`. On a device scan that
made `--projid N` alone (a) ask the backend for trusted.lov on every object
and (b) count an object with a torn layout as undecided, although its
projid is in the inode. Our own lreview found the same on 09-23
(`b2-0922/lreview-c05-0923d.txt`) and it was held.

Fix at c05 (`f1d26331de` -> `e8f1b401d6`): `find_device_want()` and
`find_rec_layout()` use `find_asks_layout()`. It is already defined above
both, so no forward declaration (Artem's remark on that does not hold).
The walk path (line ~6756 at tip) and the changelog paths are unchanged:
the walk gets projid from the stat, and the changelog paths already test
projid before `find_check_lmm_info()`.

New tip **`2efc8b116b`**: 21/21 commits build (headers, tests too); c05
checkpatch unchanged; below c05 unchanged.

Lab (`lab-projid.sh`, INTERNAL=1: mkimage's files live outside ROOT, and
`tests/find-device/run.sh` is stale for that reason -- it expects 18 and
gets 1): mkimage MDT, plus a copy whose proj1999 has a 32-byte composite
trusted.lov claiming 65535 entries.
- clean: old = new on --projid, ! --projid, --stripe-count 1, no filter.
- torn `--projid 1999`: old 0 + "1 objects could not be decided"; new 1.
- torn `! --projid 1999`: 26 both, old with the undecided warning, new none.
- torn `--stripe-count 1`: undecided in both (correct: it needs the layout).

Held, not in this fix: lreview's second point, that `--size`/`--blocks`
also ask for LAYOUT though a scan does not use the stripe count
(`path == NULL`). Needs proof the backends do not use the layout for
DoM/SOM size first.

Replies, to post only after the push (simple English):
- 3698: "Done. find_device_want() now uses find_asks_layout(), so --projid
  alone does not read trusted.lov."
- 4006: "Done. find_rec_layout() uses find_asks_layout() now. It is defined
  above this function, so no forward declaration is needed. Tested: a file
  with a broken layout is now found by --projid."


## 68163: three comments -- 2 FIXED, 1 half fixed; unpushed

Folded at c07 (`dec1b280b1` -> `74d789c1e4`). New tip **`32721e1a7a`**;
the whole stack's diff against `2efc8b116b` is m4 + libscan_zfs.c only.

1. **m4:257, probe macros:** probe CPPFLAGS now carry
   `-D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64`. Confirmed on the VM
   that the real libscan_zfs.c compile gets both (from AM_CFLAGS).
2. **m4:274, probe drifted:** probe includes `sys/spa_impl.h`,
   `sys/arc_impl.h` and names `spa_config_path`, `zfs_arc_min`,
   `zfs_arc_max`. Proven on the clone VM (ZFS 2.2.11): with a copy of the
   source header set minus `sys/arc_impl.h`, the OLD probe PASSES and the
   real compile then fails on that include; the NEW probe fails. Full
   header sets: both pass; configure sets ZFS_SCAN_ENABLED with the new
   probe; `scan_osd_zfs.so` builds with -Werror.
3. **libscan_zfs.c:536, empty/large spilled xattr:** `size == 0` now
   delivers an empty value (static empty byte, not NULL: `scan_xattr()`
   treats NULL as not read), like the SA-resident path, instead of
   dropping the object. **Kept** `size > XATTR_SIZE_MAX` as an error:
   osd-zfs sets `ddp_max_ea_size = OBD_MAX_EA_SIZE` = XATTR_SIZE_MAX, so
   Lustre never writes a larger xattr and the 70 KiB case cannot happen.
   "As an earlier revision did": no revision of this commit did.
   Lab (`zlab-empty-xattr.sh`, VM): copy of `/tmp/lfuzg-mdt1` imported as
   `a0924z`, `xattr=dir`, empty `trusted.link` on ROOT/f175 via setfattr.
   **Trap:** a ZPL-written xattr dir entry carries type bits
   (`ZFS_DIRENT_OBJ`), osd-zfs's does not, so the backend's
   `dmu_bonus_hold()` fails on a ZPL fixture before the size check. Both
   arms got a TEST-ONLY `ZFS_DIRENT_OBJ()` mask; then `--paths -type f`:
   old skips f175 ("1 of 527 skipped"), new keeps it as "no pathname"
   (2 vs 1), nothing skipped. Not put in the patch: Lustre never writes
   such entries.
   The two earlier versions of libscan_zfs.c in the stack (c07, c10)
   compile with -Werror on the VM against their own headers.

checkpatch c07: totals unchanged.

Replies, to post only after the push (simple English):
- m4 257: "Done. The probe now uses -D_LARGEFILE64_SOURCE=1
  -D_FILE_OFFSET_BITS=64, like the real build."
- m4 274: "Done. The probe now includes sys/spa_impl.h and sys/arc_impl.h,
  and uses spa_config_path, zfs_arc_min and zfs_arc_max. Tested: without
  arc_impl.h, the old probe passed and make failed. The new probe fails."
- libscan_zfs.c 536: "Done for size == 0: an empty value is kept now, as
  in the SA path. I kept the error for size > XATTR_SIZE_MAX. osd-zfs sets
  ddp_max_ea_size to OBD_MAX_EA_SIZE, which is XATTR_SIZE_MAX, so Lustre
  does not write a bigger xattr. A bigger value means the data is damaged."

Still owed before the push: lreview of c05 and c07.
VM left running: pools a0924z/a0924c exported, vdevs in /tmp/a0924{z,c};
`~/lustre-a0924` is a tarball tree (no git; server code does not build).

## 68159: fp_max_depth 0 accepted by llapi_find_device(); Fixes: tags -- DONE, unpushed

User's call on the AI's PS23 comment (pfind.c:3511). Fixed on the scan
side, NOT in `llapi_find_param_alloc()`: in a walk, `fp_max_depth` 0
already means "do not descend" (the `fp_depth == fp_max_depth` test), so
seeding -1 in the allocator would change `llapi_find()` for every caller
that leaves it zeroed. `llapi_find_device()` now accepts 0 as well as -1;
any other value is still refused. Cost: an explicit
`lfs find --device --maxdepth 0` is accepted (a scan has no top level).
`llapi_find_device.3` rewritten to say this. The changelog path (68416's
`--maxdepth` refusal) was left alone: `--since` walks and honours depth.

User's call on COMMIT_MSG:123: tags only, no split. Added before the
Signed-off-by lines (both hashes and subjects verified in the tree):
  Fixes: 6b8e97b76c47 ("LU-10378 utils: add formatted printf to lfs find")
  Fixes: 186b97e68abb ("LU-11971 utils: Send file creation time to clients")

68159 = `056dae0e01`; tip **`ca2016b752`**; stack diff vs `32721e1a7a` is
pfind.c + llapi_find_device.3 only. 21/21 build; checkpatch unchanged;
groff -ww clean. A/B (`zp-alloc-depth.c`, clean mkimage MDT, INTERNAL):
allocator param old rc=-95 / new 27 objects; 0: -95 / 27; -1: 27 / 27;
3: -95 / -95.

AI round so far (triaged, NOT yet fixed; batch after the round):
68094 x4, 68156 x4, 68095 x2, 68157 x2, 68159 x7 (two now done: 3511,
123), 68160 x2. 68159 COMMIT_MSG:109: our PS17 "Fixed in the next PS" on
Andreas's trusted.fid point was only half true, and I resolved that
thread 09-24 as "in the current patch set" -- correct it when we post.

## 68094 is final at PS26 -- follow-up change owed

PS26 = message-only (user posted it; NO_CODE_CHANGE, votes kept). User:
no more 68094 patchsets. All 68094 threads resolved; four say the work
comes in a follow-up patch:
- llapi_scan_namespace.3: print struct llapi_scan_rec and struct
  llapi_scan_param (the param listing is already on artem-0924's c00)
- pfind.c ~437 (lmd clearing comment) and ~2218 (get_projid debug
  comment): shorten to a line or two
The artem-0924 c00 must be reset to 68094 PS26 exactly before any refresh
of the rest; the struct listing moves to the follow-up.

### Local c00 reset to 68094 PS26 (done)

`artem-0924` rebased onto PS26 (`560f1a7cfa`); backup
`backup/artem-0924-pre-ps26` (= `ca2016b752`). The param listing was
stripped from llapi_scan_namespace.3 in every commit (3 conflicts: 68156,
68163, 68288, each resolved by the commit's own page minus the block).
Proven per commit: all 26 = old tree with only that block removed. New
tip **`62f0e957aa`**. Code untouched, so no rebuild. groff -ww clean.
`followup-68094-struct-listing.diff` is the c00 version; from 68156 the
listing also has `struct llapi_scan_stats *lfsp_stats` -- the follow-up
must be written against the top of the series, with llapi_scan_rec too.

## AI round 09-24: fix queue (user: fix now, locally; no push)

Bottom-up. [ ] open, [x] fixed+verified, [-] declined (reason).
- 68095 PS26: 1816 %Li/%Lo print MDT 0 off Lustre; 328 move two doc paragraphs onto the halves
- 68156 PS26: 331 LMV count vs 168-entry buffer; 798 ss_class all-or-nothing wording; 383 ext2fs_get_stat_i_blocks; 121 sink prefix ss_ -> sk_
- 68157 PS26: 2716 -ENOTSUP half-clause; 3248 decide:/decided: labels
- 68159 PS23: 27 btime walk change in body; 109 trusted.fid sentence; 1534 %Lo count==0; 3892 SPECIFIC pool reason; 4256 tgt init + probed  (3511, 123 done)
- 68160 PS24: 500 lfs-only fields in public find_param (AI: not worth reworking); 6431 82 columns
- 68288 PS17: 920 man sentence; 6464 --paths with a sweep; 3916 comment names wrong lever; 4565 fileset mount; 1599 IGIF root
- 68415 PS15: sanity.sh versions + skip; 279 statx for non-reg; 335 mask; 405 FID eq; 575 ss_emitted order; 687 cr_pfid; 693 cr_prev; 1064 copyin dup
- 68158, 68416: AI review not in yet
- 68094: follow-up change (structs in man page, two comments)

## AI round 09-24: FIXED locally (tip `a066f586de` + 68156 checkpatch fold)

Tip after all folds: see `git -C ~/lfs-artem-0924 log -1 artem-0924`.
26/26 build at every commit; libscan_ldiskfs.c compiles at every commit;
checkpatch totals identical to before the round on all 26 commits.

- 68095: [x] %Li/%Lo print nothing when the MDT index is unknown and the
  directory is unstriped (A/B off Lustre: `[0] [[0]]` -> `[] []`).
  [x] the two scan_rec_gather() rules moved onto the halves.
- 68156: [x] SCAN_LMV_BUF sized for LMV_MAX_STRIPE_COUNT (heap, 48 KB per
  worker). [x] scan_stats_whole() keeps whole ss_class elements (unit:
  47->40, 60->56, 95->88). [x] ext2fs_get_stat_i_blocks() + EXT2_I_SIZE().
  [x] sink fields ss_ -> sk_ in every commit (proven rename-only).
- 68157: [x] -ENOTSUP comment; [x] decide: -> run_decide: (decided: is
  68095's, left).
- 68159: [x] %Lo count==0 (foreign component); [x] pool-size reason is
  llapi_layout_get_by_xattr(); [x] tgt = {0} + probed; [x] message: btime
  walk change, trusted.fid left for later, pool reason.
- 68160: [x] 82 columns. [-] lfs-only fields in public find_param: AI
  itself says not worth reworking.
- 68288: [x] fileset mount refused for --fid2path (/proc/self/mounts;
  llapi_search_fileset() is declared upstream but never implemented).
  [x] --paths sweep skips non-MDTs. [x] PARENT/LINKEA comment. [x]
  lfs-find.1 sentence. [-] IGIF root: comment only; guessing ROOT could
  misname files, today it fails safely.
- 68415: [x] cr_pfid trusted only for named, non-CL_MARK records (MDS
  leaves it stale in the reused mdi_chlg_buf -- worth an upstream ticket).
  [x] cr_prev never written by any MDS: lfsr_event_prev always 0,
  documented. [x] lazy statx only for S_ISREG, and its failure keeps the
  first stat. [x] skip test uses SCAN_CL_RESOLVE_MASK (ALWAYS mask
  removed). [x] lu_fid_eq() everywhere. [x] ss_emitted counted before the
  callback. [x] sanity gate 2.17.0 (MDS side LU-19296 5b85a4eb75 is in
  v2_17_0-RC1; the 2.17.53 part is client-side) + skip_cases. [x]
  scan_cl_param_copyin() in lustreapi_internal.h.
- 68416: owed -- llapi_find_device()'s doc comment is separated from the
  function by the --since block.

Local A/B (mkimage MDT, INTERNAL): %b %s, %Lo/%Li/%Lc, %LP %m identical
old vs new on all 27 objects. NOT yet lab-proven: %Lo count==0 (my
crafted foreign-in-composite trusted.lov is rejected by
llapi_layout_get_by_xattr() itself -- fixture wrong, not the code).
Still owed: VM lab (changelog pfid/prev/statx/mask/emitted, fileset
refusal, --paths sweep, %Li on Lustre, sanity 157d), lreview.

### 68416 (AI PS15, 3 comments) -- FIXED locally, tip `fe73e1727b`
- [x] liblustreapi_scan.c + llapi_scan_fid.3: allocation is per object only
  when lfsp_want needs the MDT; LLAPI_SCAN_TYPE alone allocates nothing.
- [x] llapi_scan_test test17: a name-only case (TYPE set, no FID) and a
  directory FID (lfsr_fd open, lfsr_parent_fd -1; checked against
  llapi_scan_fid() lines ~1005). Runs on Lustre only: VM lab owed.
26/26 build; checkpatch same as before (1 warning, the man-page noise).

### 68231 (timday CR+1 PS8, one comment) -- held on branch r0924-68231
timday: the prototype comment at lustreapi_internal.h:271 is superfluous.
Agreed; not a reason to refresh (Andreas). The removal is a fixup on
branch `r0924-68231` off b7b1332a42 (= 68231 PS8), NOT on artem-0924:
68231 is the stack's base, and changing it would move 68094 off PS26.
Squash it in only if 68231 is ever refreshed. User replies on Gerrit.

### VM lab 09-24 (clone VM, 2-MDT ldiskfs, server 2.17.57_206) -- 9/10, the 1 not ours

`lab0924.sh` + `cldump.c`; arms: old = backup/artem-0924-pre-ps26,
new = artem-0924 (tip b902cb7d19 after the test17 fix below).
1. llapi_scan_test incl. test17's new cases: PASS (after fixing MY test:
   the type is reported in lfsr_stx.stx_mask as STATX_TYPE, not in
   lfsr_valid -- folded into 68416).
2. %Li/%Lo on real Lustre dirs (root, plain, 2-stripe): identical old/new.
3. changelog (cldump): parent only on MKDIR/CREAT/RENME/UNLNK, never on
   CLOSE/TRUNC/MARK; lfsr_event_prev 0 everywhere; a stopped scan: old
   emitted=0, new emitted=1. The stale cr_pfid itself did NOT reproduce
   (old arm also showed parent=0 on CLOSE) -- one client, one thread.
   llapi_scan_changelog_test test9 fails ENOENT on BOTH arms: this server
   lacks 68413 (LU-20647), so the user lookup fails. Not ours.
4. --fid2path through `mgs:/lustre/sub` on /mnt/sub: OLD prints wrong
   paths (/mnt/sub/llapi_scan_changelog_test.d/... for files not under
   sub) and exits 0 -- the AI's bug, reproduced; NEW refuses. A whole-fs
   mount is not refused.
5. `lfs find --local --paths`: old tries the OST ("has none"), new skips.
6. stopped MDT device scan, 24 objects, %LF %b %s %Li %Lo: identical.
Lab traps: under sudo $HOME is /root; the arms' PLUGIN_DIR is their own
prefix, so set LUSTRE=<tree>/lustre (the bind mount does nothing);
lfs mkdir -i 0 for the changelog test dir (DNE put it on MDT0001).
Still owed: lreview on the changed commits.

### Push plan (user, 09-24): skip changes that already have two CR+1
68231, 68094, 68095 and 68413 are not refreshed. 68095 is now exactly
Gerrit PS26 (`d2a385f08f`, on 68094 PS25 `f42d20f639`) in artem-0924; its
two AI fixes (%Li/%Lo gate, scan_rec_gather_finish() doc) moved into
68157, whose message says so. 68156 was replayed alone (changed lines
identical); every other commit keeps its exact tree. Tip `27ea1f5ffa`,
backup `backup/artem-0924-pre-keep95`. 26/26 build.
To push after master-next is rebuilt: 68156, 68157, 68158, 68159, 68160,
68163, 68288, 68415, 68416 (68417+ next week). Gates: 68158 AI review,
lreview of the changed commits, then ask.
Trap hit: a `;` after a failed `&&` chain ran `commit --amend` on the
tip; caught by comparing every message and tree with the backup.

## lreview of the 8 changed commits, 09-24 afternoon -- 27 comments, handled

Reports: ~/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_*.
Run on tip 27ea1f5ffa (68158 skipped: code unchanged since the AI's PS20).
New tip after the fixes: **`88a542200f`**. 26/26 build, ldiskfs backend
compiles at every commit, checkpatch at baseline on every changed commit.
Messages changed only on 68156, 68157, 68159, 68288, 68416.

Fixed:
- 68156: STATX_ATTR_ENCRYPTED from LMAI_ENCRYPT for every backend (osd
  clears S_ENCRYPTED from the inode); ldiskfs no longer claims it.
  Project quota inode + ea_inode inodes skipped (as osd_scrub). Message
  paragraph rewritten, Artem's credit kept.
- 68157: message: run_decide, "one comment", names LU-20605, "the split
  itself changes no behaviour" + says the carried fix changes -printf.
- 68159: a foreign LMV larger than the buffer grows it (as the walk).
  scan_linkea_entry() comment moved onto it. llapi_find_device.3 ENOTSUP
  lists the layout options over an OST and --ost/--mdt without an index;
  --maxdepth "other than 0". Message: obj:ID paragraph reduced, LMV line.
- 68160: lfs refuses any --maxdepth before the device dispatch (lfs
  seeds -1, so 0 is the user's). conf-sanity 300's redundant ldiskfs
  checks dropped.
- 68163: spa_import() ENOTSUP -> -ENOPKG; both man pages say libzpool.
- 68288: fileset detection by the mount root's FID (catches nodemap
  filesets; an IGIF root is let through); root printed as / (or MOUNT);
  test_303 gains a striped-directory case; message fixed.
- 68415: man: register with -m for sc_type_mask (LU-20647), sc_flags /
  sc_mnt / sc_stats / sc_padding entries, -ENOENT note, SEE ALSO; test2
  asserts full.cr_resolved > 0.
- 68416: -EXDEV (not -ENOENT) for a non-root mnt_fd, in the message, the
  kernel-doc and ERRORS; lfsp_got in the two lists.
Declined: 68416 #6 (move the lfsp_got hunk down to 68159): a suggestion,
cuts through 7 commits; the gap is llapi-caller-only.

Lab (VM, lab0924.sh + lab-striped.sh), old = pre-round, new = 88a542200f:
14 checks, all pass except test9 (server lacks 68413, both arms, not
ours). New since the last run: --maxdepth 0 refused (rc 95); --paths
prints / (old 0, new 1); striped dir: 10 files on MDT0000 printed as
/sd/sN, none with a shard; project quota inode 12 delivered by old, not
new. Local: an LMA-encrypted file with EXT4_ENCRYPT_FL clear is found by
new, missed by old. NOT lab-tested: the nodemap fileset, ZFS ENOPKG, a
>6 KB foreign LMV, -EXDEV (code-verified only).
Lab trap: createmany is not on root's PATH under sudo.

## PUSHED 2026-09-24 evening: 68156-68416 (9 patchsets), tag a0924-pushed

`git push review 38201dcb9a:refs/for/master` from ~/lfs-artem-0924 (user:
"if you think no more lreview is necessary, push"). 68094 PS26 and 68095
PS26 untouched (votes kept). New: 68156 PS27, 68157 PS27, 68158 PS24
(rebase only), 68159 PS24, 68160 PS25, 68163 PS24, 68288 PS18, 68415
PS16, 68416 PS16.
Second lreview (28 comments): fixed all but the declined (plugin ABI
check, %Li fix into 68095, lfsp_got move, the probe's double message).
Its must-fix pair: conf-sanity 300 lost its ZFS guards through MY 68160
edit after the first lreview (fixed at 68163), and %s/%b/%k printing 0 on
a scan with no size. No third lreview: small, reviewed diff, lab-proven.
Lab (third run): 14 pass + test9 (not ours); check 6's one change is the
striped directory whose size the scan withholds, now printed empty.
Owed now: "Done." replies on the AI PS threads and Artem's five, the
68094 follow-up change, 68417+ next week.
