# 2026-09-26: VM test of r0926b-tip before the push

**Verdict: 23/23 checks PASS. Nothing here blocks the push.** Nothing was
pushed and nothing was posted to Gerrit.

## Setup

- VM `rhel9.7-server-mgs-mds-clone` (it was shut off; started, then shut
  down again at the end). The VM's `~/lustre-release` was not touched.
- **Arms** were built from `git archive` tarballs, userspace only
  (`--disable-modules --disable-server`). Each arm has its own private
  prefix, and the ldiskfs plugin was built by hand into that prefix's
  PLUGIN_DIR:
  - **new** = `r0926b-tip` `b8c7d9c5b8`, tree `524f846172` (the same tree as
    in notes.md). Tree `~/lab0926-new`, prefix `~/arm0926new`.
  - **old** = `backup/artem-0924-pre-0926` `58b9bf3708` (r0925c-tip). Tree
    `~/lab0926-old`, prefix `~/arm0926old`.
- **Proof of which files were loaded:** LD_TRACE shows each lfs loading its
  own `~/arm0926<arm>/lib/liblustreapi.so.1`. strace shows each opening its
  own `~/arm0926<arm>/lib/lustre/scan_osd_ldiskfs.so`. `strings` checks
  showed the arms really differ: only new has "is not an MDT or an OST",
  `"%s: %llu of %llu objects were skipped"` and "ten bad calls". The make
  logs have 0 errors.
- **Modules and framework:** the installed ones. `lctl get_param -n
  version` = `2.17.58_65_g8618869` (non-empty, and checked in every run).
  lfu.ko was not loaded during the arms (no `/dev/lfu_scan`), so mounted
  targets were read by the device backend. conf-sanity 305 loads it itself.
- **Fixture:** `FSNAME=lfst`, MDSCOUNT=2, OSTCOUNT=2, formatted once. For
  the two-filesystem checks, a second filesystem `lustre` (1 MDT + 1 OST)
  was made by hand on `/tmp/lab0926-ls-*` loop files and registered with
  lfst's MGS. `/tmp/lustre-*` had the same md5 before and after.
- For each test run, the tip's `lfs` and test binaries were bind-mounted
  over `/usr/bin/lfs` and `/usr/lib64/lustre/tests/llapi_scan_*`, and
  unmounted afterwards.

Scripts, harnesses and raw logs: [`vm-lab/`](vm-lab/).

## Test suites, on the tip

| suite | result |
|---|---|
| sanity 56 (whole group) | 86 PASS, 0 FAIL, 1 SKIP (56xc: needs 2 GB free) |
| sanity 56El, 157c, 157d | PASS. 157d: test0-test10 all pass; test6 and test9 ran (not skipped); "ten bad calls refused with -EINVAL" |
| sanity 160aa, 160ab, 160ac, 160ad, 160ae | PASS (the new skip idiom runs them; none skipped) |
| conf-sanity 300, 301, 302, 303, 304 | PASS |
| conf-sanity 305 | PASS (16 s), after a fixture fix; see below |

The sanity run: `SANITY_RC=0`, 93 PASS, 0 FAIL. The two "SKIP" lines are the
same 56xc skip counted twice.

**About 305:** the first run failed with "a scan of the mounted target named
0 objects, want 20". The old arm failed the same way. The cause was my
fixture: I had not built `scan_osd_kernel.so` into the private
PLUGIN_DIR. Once it was hand-built there, **305 PASSES on the tip**. It ran
against the installed 09-17 `lfu.ko`, not a module built from the tip.
Today's changes do not touch the kernel.

## Arms (new = tip, old = r0925c-tip)

### 68415: llapi_scan_changelog(), sc_type_mask with _CLEAR
Harness `clab.c`, a changelog user registered with `-m ALL`, on
lfst-MDT0000:

| call | new | old |
|---|---|---|
| mask alone | rc=0, 5 records, index unchanged | rc=0, 5 records |
| mask + CLEAR | **rc=-22**, index 173 -> 173 (nothing cleared) | rc=0, **index 173 -> 187: records the mask never delivered were purged** |
| CLEAR alone | rc=0, index 173 -> 191 | rc=0 |

- **PASS.** On the tip, each flag alone works and the pair is refused. The
  old arm shows the defect.
- The new bad-call case ran inside sanity 157d ("ten bad calls refused with
  -EINVAL"). The old binary says "nine".

### 68160: lfs find --device / --local refusals
All run on a live node with 6 local targets:

| args | new | old |
|---|---|---|
| `--local --mindepth 1` | one line "--maxdepth, --mindepth and --threads describe a walk...", rc 95, no target opened | opens lfst-MDT0000, then fails per target |
| `--local --threads 2` | same one line, rc 95 | per target |
| `--local --maxdepth 1` | same one line, rc 95 | "--maxdepth describes a walk" |
| `--local --xattr user.x` | "--xattr needs a mounted filesystem", rc 95, no target opened | per target |
| `--device MDT --mindepth 1` | one line, rc 95 | "failed for" line as well |
| `--target MGS` | **"'MGS' is not an MDT or an OST", rc 22** | "no target 'MGS' mounted here", rc 19 |
| `--target lfst-MDT0009` | "no target ... mounted here", rc 19 (conf-sanity's grep still holds) | same |
| `--device MDT --ls` | library message "-printf %p needs a path", rc 95 | same (as designed) |

- lfs-find.1 in the tip tree lists `--ls` among the refused options: "its
  format ends in %p". **PASS.**
- A normal `--device` find works: 7 files on the live MDT0000. On the
  stopped image it gives 7 files, and new = old. **PASS.**

### 68288: naming
- **Hardlink**, on the stopped lfst MDT image, `--paths --type f`. One file
  has two names (`/hl/f0` and `/hl/hardlink`); `/hl/solo` has one:

  | args | new | old |
  |---|---|---|
  | `! --name f0` | /hl/hardlink /hl/solo | /hl/f0 /hl/solo |
  | `--name hardlink` | /hl/hardlink | /hl/f0 |
  | none / `--name f0` / `--name solo` | same | same |

  **PASS.** (The first arms run printed the correct `! --name f0` output,
  but a tag clash in my script overwrote the file it checked. I re-ran that
  case alone in `rpath-run.txt`: new `/hl/hardlink /hl/solo`, old
  `/hl/f0 /hl/solo`.)
- **Target mismatch:** `--device <lfst MDT> --fid2path /mnt/lustre`. New
  says "/dev/mapper/mds1_flakey is a target of 'lfst', not of 'lustre':
  ...", rc 18. Old says "the mount given is of 'lustre', but ...". **PASS.**
- **`--local --ost 0 --paths`:** new refuses it with "--paths names MDT
  objects only, so --ost matches no target of a sweep", rc 22. Old says "no
  local OST to search", rc 19. `--local --paths` and `--local --ost 0` alone
  still run, rc 0, and give the same output in both arms. **PASS.**
- **`--local --fid2path`**, with both filesystems' targets on the node:

  | form | new: targets read, rc | old: targets read, rc |
  |---|---|---|
  | `--fid2path /mnt/lfst` | the 4 lfst targets, rc 0, all paths under /mnt/lfst | all 6, 2 fail -EXDEV, rc 18 |
  | `--fid2path lfst` (bare fsname), cwd `/mnt/lustre` | the 4 lfst targets, rc 0 | all 6, rc 18 |
  | `--fid2path /mnt/lustre`, cwd `/mnt/lfst` | lustre-MDT0000 and -OST0000 only, rc 0, `/mnt/lustre/other/ofile` | all 6, 4 fail, rc 18 |

  **PASS.** This also proves the fix from lreview rerun #3: a bare fsname is
  not resolved through the cwd.
- **llapi_scan_rec_path() on a stopped OST.** Harness `rpath.c`: lfst-OST0000
  unmounted, the client and MDTs up, a scan with LLAPI_SCAN_F_INTERNAL, and
  rec_path called on every record that is not VISIBLE.
  - New: 292 CLS_INTERNAL records, all -ENOENT, each in 0.000 s. That
    includes `[0x280000400:0x0:0x0]`, the OST's LAST_ID. The scan finished
    with rc=0. The CLS_OST_OBJ answers were unchanged: 65 -ENOENT and 3
    named.
  - Old: it hung on `[0x280000400:0x0:0x0]` until it was SIGKILLed at 45 s.
  - **PASS.** Afterwards the OST was remounted, and the client answered.

### 68159: the skipped-objects warning names the target
On a copy of the lfst MDT image, `debugfs sif /ROOT/sk/victim links_count 0`.
Then `lfs find --device <copy> -type f`:
- New: "lfs find: /tmp/lab0926-skip.img: 1 of 280 objects were skipped:
  unreadable or inconsistent on the target".
- Old: the same message, but without the target.

**PASS.** The copy was deleted afterwards.

## VM state after the tests

- The lfst and lfsc fixtures were cleaned up, `lustre_rmmod` was run, and no
  flakey dm devices or loop devices remain. No binds remain.
- The hand-made `lustre` images were deleted. `/tmp/lustre-*` has the same
  md5 as before.
- The arm trees `~/lab0926-{new,old}` and prefixes `~/arm0926{new,old}` were
  left in place.
- The VM was shut down, as it was off at the start.

## Not covered

- Kernel code at the tip: none was built. The series' LU-20720/20730 module
  commits are unchanged today.
- ZFS: not run.
- DNE naming limits: these are documented and declined, not tested.
