# 2026-09-27: AI reviews on the 09-26 patchsets (local, no push)

Work tree `~/lfs-artem-0924`, branch `artem-0924`. Tip before: `b8c7d9c5b8`
(`r0926b-tip`), backup tag `backup/artem-0924-pre-0927`. **New tip tag
`r0927-tip`.** 26 commits, Change-Ids unchanged; 68094 (`f42d20f639`),
68095 (`d2a385f08f`) and 68158 are unchanged.

Method: `rebase -i` with `edit` on each owning commit; every fix is made
in the commit it belongs to. Conflicts: 68163 (the layout probe arm,
`spl.lfsp_search`, and the 68156 `-ENOENT` entry, which gives way to
68163's fuller one), and 68288 (the EXAMPLES; the ZFS example now comes
after the `--fid2path`/`--paths` ones, worded to stand alone). A
`git add -A lustre` picked up the untracked `lustre/utils/gss/l_gssiam_upcall`
binary into 68163; it was removed by a second rebase, and no tree
contains it (checked).

Comments: `ai-comments.md` (20, all PS on the 09-26 push).

## Per comment

| change | id | kind | disposition |
|---|---|---|---|
| 68156 PS28 | b76d9fd4 | minor | fixed: `-ENOENT` in llapi_scan_device.3 ERRORS |
| 68156 PS28 | bb99a795 | minor | fixed: page says ss_skipped also counts vanished objects |
| 68156 PS28 | 7c1ae981 | minor (ABI) | fixed: `ss_class[LLAPI_SCAN_CLS_SLOTS]`, 16, static_assert |
| 68157 PS28 | 0a97f348 | suggestion | fixed: 56El checks `%Lc%Lh%Li%Lo` prints nothing for d1 |
| 68159 PS25 | a3e82a81 | **defect** | fixed: find_tgt_index() compares a copy with the separator made `-` |
| 68159 PS25 | d314fd23 | minor | fixed: a failed probe returns its rc, no second scan |
| 68160 PS26 | 6a512e82 | **defect** | fixed: `statx(STATX_TYPE, AT_STATX_DONT_SYNC)`, stat() fallback |
| 68160 PS26 | 56404866 | minor | fixed: --local says a sweep skips the other kind, refuses both |
| 68163 PS25 | 4c284b09 | typo | fixed (message) |
| 68163 PS25 | b74d36b4 | minor | fixed: ZFS example in EXAMPLES |
| 68163 PS25 | a084a589 | suggestion | fixed the second way: comment + error hint "join its directories with ':'" |
| 68163 PS25 | dc43e70c | minor | fixed: `+ dn->dn_num_slots`, as sa_object_size() |
| 68288 PS19 | 41cdec96 | **defect** | fixed: map arm gated by find_rec_may_have_name() |
| 68288 PS19 | df006952 | minor | fixed (user, 09-27): find_device_entry() |
| 68288 PS19 | 3d052c3f | minor | fixed: doc says class, then the MDT's -ENOENT/-EINVAL |
| 68415 PS17 | 0e770de9 | minor (ABI) | fixed as doc: seconds since the epoch (header + page) |
| 68415 PS17 | 9b2b5fa0 | typo | fixed |
| 68415 PS17 | a18d496d | minor | fixed: _RESOLVE no longer asks for uidgid (lfs asks EVENT_UID itself, grep) |
| 68416 PS17 | 57365e9b | minor | fixed: "left untouched" |
| 68416 PS17 | 12eb5b6a | minor | fixed: kernel-doc, llapi_scan_fid.3 and message say MDT0; DNE may give -ENOENT |

### Verified against the tree before fixing

- **68159 a3e82a81:** `llapi_uuid_match()` strips `_UUID` then strncmp's, so
  `lfst=OST0001` vs `lfst-OST0001_UUID` is 0; libscan_ldiskfs sets
  TGT_INDEX for all four separators. Real.
- **68160 6a512e82:** `ll_getattr_dentry()` sets need_glimpse unless the mask
  has none of SIZE/BLOCKS/MTIME (llite/file.c:6299). stat() asks
  BASIC_STATS. Real.
- **68288 41cdec96:** the map arm had no class test; the lookup arm did.
  Real.
- **68163 dc43e70c:** osd_attr_get() -> sa_object_size() ->
  `(DN_USED_BYTES + 256) >> 9 + dn_num_slots`; doi_physical_blocks_512 is the
  same without the slots. dn is still held at that line.
- **68156 7c1ae981:** ss_class arrived in 68156 itself, not frozen 68094.

### 68288 df006952: the other linkea entries (fixed after the user said so)

True: only entry 0 (or the one --name matched) was composed. New
`find_device_entry()` in find_device_cb(): with the map built and a
hardlinked object of a named class, walk the linkea once
(`scan_linkea_next()`), skip entries --name rejects (`find_prefilter()`
on a copy of the record carrying that name and parent), and take the first
whose path does not come back -ENOENT; otherwise the entry the prefilter
chose. The commit message now says an object is nameless on DNE when none
of its links has its parent path on this MDT. LU-20722 conflicted (a new
neighbouring function); both kept. Backup before: `backup/artem-0924-pre-0927b`.
Reply: `Done. The first entry --name matches and the map can place is used.`

## Verification

- Build sweep (`../a-0925/sweep.sh`): **24/24 clean** incl. libscan_zfs
  from 68163 up; `sweep.log`.
- checkpatch (per commit, new vs old): totals identical on all eight.
- Re-sweep after the df006952 fix, 68288 up (`sweep-b.log`): **18/18 clean**, tip `73d04cd04d`.
- lreview: `lreview/` (68416 skipped: docs, comments and message only).
- VM lab (`vm-test.md`), on 73d04cd04d vs b8c7d9c5b8: **all green** — sanity 56 86/0 (+56El, 157c/d, 160aa-ae), conf-sanity 300-305; A/B shows every fix: label separators 63 vs 0, error once vs twice, statx TYPE + 0 glimpses vs 2, orphan path gone, remote-hardlink /dh0/f2 printed, ZFS blocks = client (old 2 lower), sizeof stats 168 vs 96.

## lreview on the changed commits (default settings: full, opus)

| change | result | disposition |
|---|---|---|
| 68156 | 2 low | rdev decode: already our 69206 (LU-20832), no action; hardlink = one record here, noted in llapi_scan_device.3 |
| 68157 | clean | |
| 68159 | 2 low | **commit-message bullets Andreas flagged on PS17 (c6692d26) were still there, word for word, though we said "Fixed in the next PS"** -> trimmed to one sentence; llapi_find_device.3 layout list gains --stripe-size, --extension-size |
| 68160 | 3 low | message: "nothing mounted" only for --device / block device; names statx(); lfs-find.1 --internal says a FID-less object prints as obj:ID |
| 68163 | 3 low | ENAMETOOLONG off by one, fixed; two conf-sanity ZFS suggestions (assert EBUSY on an imported pool; narrow the no-backend skip) **held for the user** |
| 68288 | 1 low | on bfd6650d32 (includes df006952): lfs-find.1 now says CAP_DAC_READ_SEARCH *unless llite.*.user_fid2path is set*, fixed (docs only, tip 07236a95a7) |
| 68415 | 3 low | all real, fixed in 68415 (62507e5a43), see below |
| 68416 | skipped | docs, comments and message only |

Applied by scripted rebase (backup `backup/artem-0924-pre-0927c`), one
conflict at 68163 (lfs-find.1, --internal vs the new --search entry, both
kept). Diff to the previous tip is three man pages only; code per commit is
unchanged, so the sweeps stand. `r0927-tip` = `b552d89a6b`.
After this, Andreas's 68159 thread c6692d26 should get a short reply with the push.

## 68163: lreview's two ZFS test suggestions, added (user, 09-27)

- conf-sanity 300, ZFS, mds1 up: `lfs find --target $mdt1svc` must fail with
  "in use: pool imported" (or the build has no backend).
- `zfs_scan_unbuilt()` replaces the three `grep "Operation not supported"`
  skips: ENOTSUP is a skip only when every dlopen() said
  `scan_osd_zfs.so: cannot open shared object file`.
- For that, scan_backend_load() now reports both dlopen() errors
  (PLUGIN_DIR; $LUSTRE/utils). Before, the fallback's "cannot open" hid a
  broken plugin in PLUGIN_DIR.
- Helper tested 7/7 in a clean bash, pipefail on and off, and on real lfs
  output: absent -> skip, both absent -> skip, broken fallback -> FAIL.
  Trap on the way: this workstation's profile defines `grep` as a shell
  function, which made the interactive table lie; the first `tr | grep -q`
  form also risked SIGPIPE under pipefail, so it is pipe-free now.
- checkpatch unchanged (0/2). Sweep from 68163 up: `sweep-c.log`, **19/19 clean**.
  ZFS conf-sanity 300 A/B on the VM: vm-test.md follow-up section.
  lreview rerun on the new 68163 (0439ba0ba2): `lreview/run-68163b.log`.

## 68415: lreview's three findings, fixed

1. **Lazy size 0 marked lazy.** llite answers AT_STATX_DONT_SYNC with
   lli_lazysize only when the MDT sent OBD_MD_FLLAZYSIZE (file.c:6449);
   else i_size, 0 on a fresh inode. Now LAZY_SIZE / LAZY_BLOCKS are set only
   for a nonzero value. An empty file with SOM loses the lazy bit: no answer
   rather than a wrong one. Page and message say so. lfs find always asks
   SIZE, so it glimpses and is unaffected.
2. **Resolved times lost ns.** scan_cl_mdt_stat() returns the struct statx
   (plus STATX_BTIME); the fstat() fallback converts. The no-statx branch
   syntax-checked with HAVE_STATX undefined.
3. **CL_MIGRATE delivered the old FID as a second object.** mdd_migrate()
   and the layout-split path pass the old FID as sfid with a source name
   (mdd_dir.c:5123, 5653), so CLF_RENAME is set. scan_cl_rec_fids() now skips
   cr_sfid for CL_MIGRATE; page and message say so.

Build ok; checkpatch unchanged (0/2). Sweep from 68415 up: `sweep-d.log`, **17/17 clean**. **18/18 clean**.
VM A/B: vm-test.md "follow-up 2". lreview rerun: `lreview/run-68415b.log`.

## VM follow-ups (vm-test.md, both PASS)

- 68163 on ZFS (719b60f73e): conf-sanity 300 PASS with the plugin; the
  --target call answered "in use: pool imported" (rc 16). Non-ELF plugin:
  FAIL, not SKIP, message names both dlopen() reasons. Plugin absent: SKIP.
  A truncated .so kills lfs with SIGBUS inside dlopen() -- the loader, not
  ours, but a short plugin file is fatal. ldiskfs conf-sanity 300-305 6/6
  on 133643bd9e.
- 68415 (133643bd9e vs b8c7d9c5b8): 157c/d, 160aa-ae 7/7. CL_MIGRATE record
  188 once (new) vs twice with the dead old FID (old). Open-for-write file
  with no SOM: lazy_size bit clear (new) vs set with size 0 (old); a closed
  file keeps it in both. btime filled on new. Nanoseconds not demonstrable:
  the client itself reads .000000000 on this setup.
- lreview rerun on the new 68163 (0439ba0ba2): **clean**.
- lreview rerun on the new 68415 (62507e5a43): 2 low, both real.
  1. BTIME, filled since today, was missing from SCAN_CL_RESOLVE_MASK: a
     want of BTIME alone skipped the resolve and sc_got never said it.
     Added. (T7 checks sc_got as a subset, unaffected.)
  2. mdc_changelog.c:814 stores in.cf_mask & out.cf_mask and :222 takes 0
     as no filter, so a sc_type_mask disjoint from the user's mask delivers
     everything. Upstream mdc; the page now warns. **Candidate LU ticket,
     not filed (ask the user).**
  Fixed in 68415 = 9d886a6269, tip r0927-tip = 3636a0b9d1. checkpatch 0/2,
  sweep-e 17/17. Third lreview on 68415: `lreview/run-68415c.log`.
