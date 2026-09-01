# Round 17 — the 2026-09-01 AI sweep

45 inline AI comments across 13 changes, all landing overnight 08-31/09-01 on
the round-16 patch sets.  Plus 14 checkpatch comments (68157, 68158, 68417),
all in the known-noise class: verbatim-moved code from `lfs.c`, and a `time_t`
false positive.

Branches: `r16-work` (16-commit stack) and `r16-pair` (mdd/mdc), with
`backup-pre-r17-2026-09-01` / `backup-pre-r17-pair-2026-09-01` beside them.

## The lab found a defect in the 68288 fix

The first lab build passed sanity 14/14 but failed the targeted check for the
new wrong-filesystem guard: it never fired.

`mkfs.lustre` encodes registration state in the target label's separator --
`fsname-MDT0000` once registered, `fsname:MDT0000` never mounted,
`fsname=MDT0000` after writeconf, `fsname+MDT0000` after `--nolocallogs`.
`scan_device_fsname()` split on `strrchr(label, '-')`, so it found an fsname
for one of the four and `-ENODATA` for the other three, and the "nothing to
compare, carry on" fallback then let the scan run.  The form it got wrong,
`:`, is the one a device scan is most likely to meet: a target that has never
been mounted.

`scan_ldiskfs_label()`, twenty lines away, already had this right -- the
target part is the last eight characters, and it reads all four separators.
The fix now uses the same rule and additionally requires the backend to have
recognised the target (`tt_flags`).

Worth remembering: this was a second, wrong parser written next to a correct
one, and no amount of desk review had caught it.  Only a target formatted and
never mounted shows it.

## Verified defects fixed

| Change | Finding |
|---|---|
| 68288 | **The wrong-filesystem claim was false.** `LUSTRE_SEQ_SPACE_RANGE.lsr_start = FID_SEQ_NORMAL` is the same constant on every filesystem and `FID_SEQ_ROOT` is a literal, so `--fid2path` against another filesystem's mount resolved and printed *its* paths, exit 0.  Added `scan_device_fsname()` and an up-front `-EXDEV` refusal; corrected the claim in the code comment, `lfind.8`, `llapi_scan_rec_path()`'s Return: block and the commit message. |
| 68159 | `find_lmm_fits()` applied a blanket 32-byte floor before reading the magic, but a legal foreign LOV EA is 16+len.  A 19-byte one took the no-layout path and got a forged default, so `--foreign` missed it.  Floor is now per-magic (4 bytes to read `lmm_magic`; each arm carries its own). |
| 68416 | The `open_parent()`/`opendir()` ran unconditionally although `scan_rec_gather()` returns early when `want` has nothing in `LLAPI_SCAN_MDT_MASK` — the name-only mode paid a descriptor it never read and inherited its EACCES.  Moved under the mask.  Same cause meant the `-ESTALE` guard never fired there; documented rather than paying an ioctl to fix. |
| 68418 | `find_changelog_needs_lookup()` omitted `-uid`/`-gid` and `--mdt-count`/`--mdt-hash`, so with `--resolve` a gone object was decided from zeroes (or never evaluated).  Added. |
| 68418 | A nameless changelog record was `fnmatch()`ed against `""` — and `-name '*'` matches `""`, so the code comment was wrong too.  `find_prefilter()` now leaves a nameless record alone and `find_changelog_rec_cb()` counts it undecided, as it already did for `-type`. |
| 68415 | `CL_MARK` passes `fid_is_sane()`: the marker flags land in `cr_tfid` as `[CLM_START:0:0]` and `0x10000` is inside `FID_SEQ_IGIF`.  Marks were coalescing into one entry.  Now tested on `cr_type`. |
| 68415 | `cr_namelen` spans both names on a `CLF_RENAME`; bounded with `strnlen()` as `lustre_rsync.c` does. |
| 68415 | The `sc_size >= offsetof(...)` guard was dead — `sc_size` had been overwritten with `sizeof(scl)` nine lines earlier.  Now tests `sc_padding` alone. |
| 68415 | `ss_seen` counted the record that ended an `sc_endrec` range; moved below the bound. |
| 68419 | A cookie in the root directory left `tmp` empty and `open("")` failed, so the directory fsync never happened. |
| 68419 | The `fss_reached` anchor sat below the FID gate, so it lagged by whatever trailing run of FID-less records (CL_MARK, `mv a b` onto a new name) the scan ended on.  Moved above. |
| 68419 | Dead `cookie != NULL` test — the one caller checks it and the -ESTALE message uses it unguarded. |
| 68413 | `strscpy(reply->cf_username, rec->cur_name, sizeof(reply->cf_username))` — a 30-byte bound on a 16-byte field, on the field the `strncmp` above was just bounded on. |
| 68413 | The 80-byte record came from a15eb4f132 (LU-13055, v2.14.53), not LU-19296 — that commit changed `rec` from `llog_changelog_user_rec *` to `_rec2 *`, so `sizeof(*rec)` went 40→80. |
| 68420 | The `--since`/`--since-cookie` and two-path refusal cases ran *after* the cookie was deliberately made stale, so both passed on `-ESTALE` without reaching the refusal they name.  Moved above that section. |
| 68095 | 68095's ENOTTY change let a walk descend a non-Lustre directory, so its files reach `printf_format_string()` and every `%L` directive prints an error line per file.  `%LF` and the shared layout fetch now stay quiet on ENOTTY. |

## Behaviour changes beyond the defects

- `--since` now accepts the two today-relative forms (`18:00`, `18:00:30`) that
  `-newerXt` documents, seeded with `localtime_r()` the same way.  The bare
  `%s` stays out: an unqualified number is an index.
- `68419`'s `find_device_supported()` hunk was split — the `--changelog`
  refusal moved down to 68418, where the option is introduced, so `lfind
  --changelog all` is not silently accepted at that commit.
- New sanity coverage in 160aa for `@N` vs bare `N`, the ISO timestamp, and
  the refused spellings.

## Declined, with reasons

- **`lustreapi.7` index entry (68417).** Worth having, but adding one section
  makes `checkpatch-man` lint the whole page, which fails on 46 pre-existing
  items — 29 malformed SEE ALSO lines, an unsorted list, a 2024 date and a
  missing AVAILABILITY release line.  Belongs in its own patch.
- **Renaming `find_prefilter()` (68095).** It is used across eight commits of
  the stack; the inverted sense is now spelled out in its comment instead.
- **`-atime`/`-mtime` as undecided on a target scan (68159).** Marking them
  undecided would make `lfind -mtime` answer nothing for every striped file.
  Documented in `llapi_find_device.3` instead.
- **Reusing `llapi_scan_rec_path()` in `llapi_scan_fid()` (68416).** Changes
  the error from `-ENAMETOOLONG` to `-ERANGE`, which the man page states.
- **The dead `LLAPI_SCAN_INO` arm (68288).** Dead at 68288, live from 68418 on
  (a changelog record carries no inode number), so it stays.

## Verified

- `make -C lustre/utils` clean under `-Wall -Werror`.
- `mdd_changelog.o` and `mdd.ko` rebuilt on the RHEL 9.7 MDS VM
  (`~/lustre-160ac`), rc=0; the VM tree was restored afterwards.
- checkpatch per patch: no new findings beyond the "Comparison to NULL" class
  this file has carried for sixteen rounds; no ERRORs anywhere; the pair is
  clean.
- `bash -n lustre/tests/sanity.sh`.
- The `--since` parser exercised directly: `18:00`, `18:00:30`, `2h`,
  `@1787674596`, `2026-08-25T18:00` and `4200` parse; `-5`, `2h30m` and the
  empty string are refused.
- 16 Change-Ids, base unchanged at 5afbab284e.

## The lab run

On `rhel9.7-server-mgs-mds-clone`, tree `~/lustre-160ac` branch `lab-r17` =
the 16-commit stack with the mdd/mdc pair cherry-picked; `git diff lab-r16
lab-r17` is this round and nothing else.  MDSCOUNT=2, OSTCOUNT=1, ldiskfs,
`ONLY_REPEAT=2`.

The installed binaries were confirmed to be this round by grepping the
installed `lfs` for strings only round 17 introduces -- the version string
reads `2.17.57_62_g20e1f0f`, a stale configure-time describe that says
nothing.

**sanity, on the final build: 14/14 PASS, 0 SKIP.**

    157c PASS:2  160aa PASS:2  160ab PASS:2  160ac PASS:2
    160ad PASS:2  160y PASS:2  160z PASS:2

**The targeted checks**, for the defects with no subtest of their own
(`15-r17-guard.sh`, `14-r17-targeted.sh` on the VM):

- 68288: a never-mounted `otherfs:MDT0000` on a loop device is refused with
  *"'/mnt/lustre' is a mount of 'lustre', not of 'otherfs'"*; a
  `lustre:MDT0000` control is not refused, and `--internal` reports 4 objects
  on it, so the control is not passing merely because the scan did nothing.
- 68159: `lfs setstripe --foreign=none --xattr=abc` gives a 19-byte
  `trusted.lov`, and `--foreign` finds the file.
- 68095: a tmpfs under `/mnt/lustre` produces no `cannot get` lines on stderr
  from `-printf '%p %Lc\n'`, and the walk still reaches both objects.

**conf-sanity, on the final build: 165 PASS:2, 166 PASS:2, 0 SKIP.**  166 is
the `--fid2path` case, so it also covers the guard's legitimate path: it
created 20 objects under 21 names, resolved every one through a client
mounted on the MDS, and counted the hardlink once.  It reports in 0-1s, which
is the test being small and not the test being skipped -- the log carries the
object counts.

**One comment was reworded after the run.**  `git diff` between the tree the
lab built and the final tree touches only comment lines in
`liblustreapi_scan_device.c`; no code line differs.

**Not covered by this lab: the ZFS path.**  The guard opens the target a
second time, and for ZFS that is a pool import.  `--fid2path` on ZFS means a
stopped target, so import/export/import should be fine, but it was not
exercised -- the lab is ldiskfs only, which is also what conf-sanity 166
restricts itself to.
