# 2026-09-26: AI reviews on 68159, 68160, 68288, 68415, 69206 (local, no push)

Work tree `~/lfs-artem-0924`, branch `artem-0924`. Tip before: `58b9bf3708`
(`r0925c-tip`), backup tag `backup/artem-0924-pre-0926`. **New tip
`85e6ddacff`, tag `r0926-tip`.** 26 commits, Change-Ids unchanged. 68094
(`f42d20f639`), 68095 (`d2a385f08f`), 68156, 68157 unchanged.

Method: the fixes were made at the tip, split per owning commit
(`fix-68159.diff`, `fix-68160.diff`, `fix-68288.diff`, `fix-68415.diff`,
from `full.diff`), committed as `fixup!` commits and autosquashed. The
68160 message came from `msg-68160.txt` through an `exec` step
(`seqed.sh`). The tree after the rebase equals the tree of the fixups
(`b78cc73082`). range-diff: only 68159, 68160, 68288 and 68415 change;
LU-20650 `--changelog` and LU-20722 show `!` with only context changed
(checked).

69206 PS1 (LU-20832 rdev): the AI said "Looks good to me", no inline
comments. Nothing to do.

## Per comment

| change | id | kind | disposition |
|---|---|---|---|
| 68415 PS16 | 5bc8e33a_b38ee5ac | minor | fixed |
| 68415 PS16 | 774be013_25e011fa | style | fixed |
| 68415 PS16 | ead168b4_a7824a82 | defect | fixed (refused) |
| 68288 PS18 | 86ee5f6a_2ebb75ca | suggestion | declined |
| 68288 PS18 | 4c1ecc39_2240f789 | minor | fixed |
| 68288 PS18 | 40706fae_8aa9d6d7 | style | fixed |
| 68160 PS25 | c71bbbab_8fe92ea5 | minor | fixed (message) |
| 68160 PS25 | 3a1ac517_b0bc7642 | minor | fixed, %p left to the library |
| 68159 PS24 | 0fddf7f1_f535a11d | style | fixed |
| 68159 PS24 | 63f1ecc8_975f7f78 | style | declined |
| 68160 (board) | `-f`/`--foreign` | owed | added to the message |

### 68415 5bc8e33a: sc_stats "filled as the scan runs"
True: counters live in `sl->sl_stats` and are copied out at `out:`. The
sentence now says "filled in when the scan ends".
Reply: `Done.`

### 68415 774be013: LLAPI_SCAN_CL_PARAM_MIN_SIZE in the public header
True: the only `offsetof()` in lustreapi.h, used only by
`scan_cl_param_copyin()` in lustreapi_internal.h, not documented. Moved to
lustreapi_internal.h next to `LLAPI_SCAN_CL_F_KNOWN`, with a two-line
comment. No other user in the stack (grep at the tip).
Reply: `Done.`

### 68415 ead168b4: sc_type_mask + _CLEAR purges unseen records (DEFECT)
True. The mdc drops records outside the mask, and
`llapi_changelog_clear()` clears everything up to the index for the user.
Fix: `llapi_scan_changelog()` returns -EINVAL for `sc_type_mask != 0` with
`LLAPI_SCAN_CL_F_CLEAR`. Man page: the `sc_type_mask` entry and ERRORS say
so. `llapi_scan_changelog_test.c` bad-call section: a tenth case ("ten bad
calls refused"). Nothing in lfs uses a mask (grep), so `lfs find` is not
affected.
Verified: harness `clh.c` against the new liblustreapi (no Lustre needed,
the check comes before the device open): mask+CLEAR rc=-22; mask alone
and CLEAR alone get past validation (rc=-2, no such MDT). The old code has
no such check (read, not run).
Reply: `Done. _CLEAR with sc_type_mask is now refused with -EINVAL, and the
man page says why.`

### 68288 86ee5f6a: resolve missing ancestors through the mount (declined)
The limit is real and already documented: lfs-find.1 says an object has no
pathname "under DNE, an object whose ancestors are on another MDT". A
lookup through the mount may reach the stopped target, as the AI notes.
Doing it only for a target in service is LU-20722's scan, not this one.
Reply: `Not in this patch. lfs-find.1 already says it: under DNE an object
whose ancestors are on another MDT has no pathname. A lookup of the missing
ancestor is possible for a target in service; that belongs with LU-20722.`

### 68288 4c1ecc39: "the mount given" when there is no mount
True: `want_fsname` also comes from `lfsp_fsname`. Message now
"%s is a target of '%.*s', not of '%s': FIDs from one filesystem resolve on
another and would print its paths". No test greps the old text.
Reply: `Done.`

### 68288 40706fae: comments that describe earlier revisions
True for all five. Each now says what the code does: the pre-pass test
(label, not map contents), `scan_dirmap_cb()` (linkea name is not a path
element), `scan_dirmap_prepass()` (same open), `find_device_cb()`
(fds_dirmap_built), `find_decide()` (-EINVAL: every OST has LAST_ID).
Reply: `Done.`

### 68160 c71bbbab: "-F is --fid"
True: `lfs find` has no -F; `fid` is commented out in the table. Message
now: "There is no short option, to keep -F free for --fid, as in lfs
getstripe." The owed `-f`/`--foreign` paragraph (promised on PS22,
thread 50823bd8) is added next to it:
"A second f* long option makes "--f" ambiguous: "lfs find --f" and
"lfs find -f" (which getopt_long_only() reads as a long option) meant
--foreign before, and are now refused. "--fo" still works."
Reply (c71bbbab): `Done.` Reply (50823bd8, when pushed): `Done, in the
message.`

### 68160 3a1ac517: refuse target-independent options once
True. `lfs_find_device()` now refuses --maxdepth, --mindepth, --threads
(one message) and --xattr before any target is opened. `-printf %p` is
left to the library: only it parses the format (`printf_format_want()` is
internal). fp_thread_count is still 0 here, because lfs sets the walk's
default later, on the walk's arm (checked at the tip).
Verified with the built lfs on this host: `--local --mindepth 1`,
`--threads 2`, `--maxdepth 1`, `--xattr user.x`, `--device /dev/null
--mindepth 1` each print one refusal, rc=95, before the target lookup.
Not run on a node with several targets (VM was off); the ordering is
proven by the runs above.
Reply: `Done for --mindepth, --threads and --xattr. -printf %p stays in
the library, which is the only place that parses the format.`

### 68159 0fddf7f1: printf_scan_lacks() between a comment and its function
True. Moved above the comment block. `@param rec` added to
`printf_format_directive()` and `printf_format_lustre()` (the argument
came from 68095, which is frozen; the doc line lands here).
Reply: `Done.`

### 68159 63f1ecc8: make llapi_uuid_match() const (declined)
Right, but it changes a public prototype of landed code in a feature
patch. Better as a small cleanup of its own.
Reply: `Agreed, but it changes a public function this patch does not
otherwise touch. I will do it in a separate cleanup patch.`

## Verification

- Build sweep (`../a-0925/sweep.sh fb5ef60405 HEAD`): **23/23 clean**,
  `SWEEP fb5ef60405..85e6ddacff` (utils, public header, three scan test
  programs, both backends, -O2 -Werror). Log: `sweep.log`.
- checkpatch, old vs new, all four changed commits: identical totals
  (baseline).
- `groff -ww` on llapi_scan_changelog.3: clean.
- Own diff re-read (`full.diff`, 60+/50-).
- **Not done:** lreview of the four changed commits (standing rule before
  any push), and a VM lab (behaviour changes are argument checks only, run
  locally as above).

## Owed

- lreview 68159, 68160, 68288, 68415 before the push-ask.
- Follow-up cleanup: `llapi_uuid_match()` const.
- Replies above go with the push.

# 2026-09-26 (b): lreview on 68159, 68160, 68288, 68415 (local, no push)

Reports copied to `lreview/`: dba64d2b45 (68159, 1), 8f9491da33 (68160, 2),
27612338b6 (68288, 2), edc3172d53 (68415, 3). All eight verified against
the tree; all eight real. Seven fixed, one half-declined.

Tip before: `85e6ddacff` (`r0926-tip`), backup tag
`backup/artem-0924-pre-0926b`. **New tip `b8c7d9c5b8`, tag
`r0926b-tip`** (tree `524f846172`). 23 commits above fb5ef60405,
Change-Ids unchanged. 68094/68095 untouched.

Changed commits: 68159 `b59bac96ca`, 68160 `bf31230deb`, 68288
`5109e6f204`, 68415 `97ccf0f948`, LU-20650 tests `70b8adfb60` (ripple),
LU-20722 `24d9e75a76` (one kernel-doc paragraph, ripple from 68288).
Everything else changes only in context.

Method: fixed at the tip, tree recorded, split into `fixup!` commits per
owning commit, autosquashed; final tree = recorded tree after every fold.
The 68288 and 68415 messages come from `msg-68288-b.txt` and
`msg-68415-b.txt` through `exec` steps (`seqed-b.sh` for the first fold,
`seqed-c.sh` for the later 68288-only folds). The first fold stopped on two
conflicts, resolved with `git add` + `--continue` only, never amend: the
68288 fixup (at 68288 the nobytes and -links code does not exist yet;
kept HEAD's side plus the fix) and 97316b4e34 (no later commit touches
lfs-find.1 or pfind.c, so both files taken from the recorded tree).
range-diff after every fold: only the intended commits change.

## Per finding

| change | commit | finding | kind | disposition |
|---|---|---|---|---|
| 68159 | dba64d2b45 | 1 skipped warning has no target | style | fixed |
| 68160 | 8f9491da33 | 1 `--ls` refused as "-printf %p" | minor | fixed (man page); by-name refusal declined |
| 68160 | 8f9491da33 | 2 `--target MGS` says "not mounted" | minor | fixed (code) |
| 68288 | 27612338b6 | 1 hardlink printed under entry 0, not the matched name | minor (real defect) | fixed (code); DNE "first placeable entry" part declined |
| 68288 | 27612338b6 | 2 man page: OST prints a file once per object | minor | fixed |
| 68415 | edc3172d53 | 1 message: test9 needs -u too | minor | fixed |
| 68415 | edc3172d53 | 2 test header: register with -m ALL; usage() | minor | fixed |
| 68415 | edc3172d53 | 3 negated `[[ ]] && skip` | style | fixed, and the same 5 lines in e7a6896985 |

These are local findings, not Gerrit threads, so no reply is owed. Draft
lines are for a reviewer who raises the same point.

### 68159 #1: "N of M objects were skipped" has no target
True: the only warning in `llapi_find_device()` without the target. Now
`"%s: %llu of %llu objects were skipped: ..."`. Ripple: 68288 adds a
second one ("... skipped while mapping directories"), also without the
target; fixed the same way in 68288. No test greps either text.
Draft reply: `Done.`

### 68160 #1: --ls is refused under another option's name
True: `--ls` sets `fp_format_printf_str` to a format ending in `%p`, and
the library refuses "-printf %p needs a path". Reproduced on this host
against an image: `lfs find --device mdt.img --ls` -> that message, rc=95.
Fixed in lfs-find.1: `--ls` added to the refused list, with "--ls is
refused because its format ends in %p". Refusing it by name in lfs is
declined: lfs sees only the format string, the same as a -printf the user
wrote, and only the library parses formats.
Draft reply: `Done in lfs-find.1. lfs cannot tell --ls from the same
-printf string, so the library message stays.`

### 68160 #2: --target MGS says "no target 'MGS' mounted here"
True: `lfs_find_local_targets()` drops every label that is not -MDT/-OST
before comparing it with @want. Fixed: `lfs_find_device()` refuses a
`--target` that is not an MDT or OST label before the target lookup:
`find: 'MGS' is not an MDT or an OST`, -EINVAL. conf-sanity's
"no target '$svc' mounted here" still holds for an MDT name (checked:
`--target testfs-MDT0000` and `testfs-OST0001_UUID` still give that
message, rc=19).
Draft reply: `Done.`

### 68288 #1: a hardlink printed under a name --name did not match (DEFECT)
True. `find_device_prefilter()` tries --name against every linkea entry,
but `find_decide()` composed the path from `lfsr_name`, always entry 0.
Fix: the prefilter returns the index of the entry that matched, and
`find_device_cb()` passes `find_decide()` a copy of the record with that
entry's name and parent (`scan_linkea_entry()`), only when the index is
not 0.
Proven A/B on this host, `lfs find --device mdt.img --paths --type f`,
one file with two names (f0, hardlink) under ROOT plus one single-name
file (solo), plugin built from the tree:

| args | unfixed (r0926-tip lib) | fixed |
|---|---|---|
| `! --name f0` | /f0, /solo | /hardlink, /solo |
| `--name hardlink` | /f0 | /hardlink |
| (none), `--name f0`, `--name solo`, `! --name solo` | same both | same both |

The DNE part (entry 0's parent on another MDT, a later entry's parent in
this MDT's map) is declined: without --name, which name to print is a
choice, fid2path also answers with the first link, and under --fid2path
the mount lookup already names the object. lfs-find.1 documents the DNE
limit.
Draft reply: `Done: the path is now composed from the entry --name
matched. Trying every entry against the map for a DNE object is left out;
--fid2path names it through the mount.`

### 68288 #2: lfs-find.1 says "printed once"; an OST prints once per object
True. lfs-find.1 now says: a hardlinked file is printed under the first
name --name matches, or else its first name; on an OST a file is printed
once per object there, so a composite or overstriped file may repeat;
use `sort -u`. The commit message says the same.
Draft reply: `Done.`

### 68415 #1: commit message says only test6 needs -u
True: test9 skips without -u too. Message now: "test6 and test9 need it
and skip without one: test6 clears, which cannot be undone, and test9
filters through the user."
Draft reply: `Done.`

### 68415 #2: test header tells the user to register without -m ALL
True: a maskless user makes test9 fail (LU-20647), which 157d avoids with
`-m ALL`. Header now `changelog_register -m ALL`, with one line why, and
"Without -u, test6 and test9 skip". usage(): "-u  a registered Changelog
user, to clear and to filter". `lctl changelog_register` takes `-m`
(checked in lctl.c).
Draft reply: `Done.`

### 68415 #3: `[[ $PARALLEL == "yes" ]] && skip`
True. 157d now uses `[[ $PARALLEL != "yes" ]] || skip`. Ripple: the same
negated line in 160aa, 160ab, 160ac, 160ad and 160ae (e7a6896985, LU-20650
tests) changed too, so the series is consistent. Other upstream tests keep
theirs. `remote_mds_nodsh && skip` is the tree's own idiom and stays.
Draft reply: `Done.`

## lreview reruns (one at a time, sequential)

Rule used: rerun only a commit whose fix changed code non-ignorably.
The user capped it at rerun 4 on 68288 (message from the coordinator):
fix real defects rerun 4 finds, no rerun after that, nits deferred.

| run | commit | findings | tokens | cost | time |
|---|---|---|---|---|---|
| 68288 #1 | f3a40d5fce | 1 | 4.6M | $3.02 | 5m43s |
| 68160 #1 | 465bc31421 | 1 | 6.5M | $3.28 | 6m36s |
| 68288 #2 | 21a9fe3a6d | 3 | 5.0M | $3.02 | 6m15s |
| 68288 #3 | 560854e59d | 2 | 5.7M | $3.21 | 5m28s |
| 68288 #4 | 10fe4e1b20 | 1 | 4.9M | $3.05 | ~6m |
| total | | 8 | 26.7M | $15.58 | |

Skipped, and why:
- 68159: the fix adds `"%s: "` and `target` to a warning's format; -Wformat
  with -Werror checks the pairing. A message, not logic.
- 68415: commit message, a test comment, a usage() string and a sanity.sh
  idiom. No behaviour.
- LU-20650 tests (e7a6896985): the same sanity.sh idiom, five lines.
- LU-20722: one kernel-doc paragraph.

Reports and logs are in `lreview/` (`rerun*-*.log` and the `.md` files).

### 68288 #1, f3a40d5fce: `--local --ost 0 --paths` says "no local OST" (fixed)
True: --paths skips every OST and --ost skips every MDT, so nothing is
left, and the message blames the node. Now refused up front, next to the
--ost/--mdt check: "--paths names MDT objects only, so --ost matches no
target of a sweep", -EINVAL. Commit message: "and refuses --ost".
Checked here: rc=22 with that message; `--local --paths` and
`--local --ost 0` alone unchanged.

### 68160 #1, 465bc31421: a sweep hands OSTs the layout options (declined)
Suggestion: skip OSTs when the search has layout predicates, as --mdt
does. Declined for now: lfs-find.1 documents the per-target -ENOTSUP, the
function's comment says ENOTSUP does not end a sweep on purpose, and lfs
would need its own copy of the library's list of layout options
(`find_asks_layout()`), which is internal. Left for the user to decide
(see the report).

### 68288 #2, 21a9fe3a6d: three findings
1. **`--local --fid2path MNT` on a node with two filesystems** (fixed):
   targets of the other filesystem each failed -EXDEV and the command
   exited non-zero. Now a `--local` sweep with `--fid2path` reads only the
   targets of the mount's filesystem (lfs passes it to
   `lfs_find_local_targets()`). lfs-find.1 and the commit message say so.
   Not run: this host has no Lustre mount; needs the VM to prove.
2. **llapi_scan_rec_path() on a stopped MDT waits** (fixed, docs): NOTES
   in llapi_scan_rec_path.3 and the kernel-doc now say an MDT object is
   resolved by that MDT, so only while it is in service; the man page
   points to `llapi_find_device()` with `fp_paths` for a stopped MDT.
3. **`sd_` prefix shared by struct scan_dirent and struct scan_dev**
   (declined): a rename over a 2,000-line commit and the ones above it,
   for grep convenience. Deferred.

### 68288 #3, 560854e59d: two findings
1. **DEFECT in my #2.1 fix**: `llapi_search_fsname()` reads its argument
   as a path, so a bare fsname (`--fid2path testfs`) resolved to the
   filesystem of the cwd. Fixed: an argument that does not start with '/'
   is the fsname itself, as `llapi_find_device()` reads it
   (`llapi_search_rootpath()`). Not run (no mount here).
2. **llapi_find_device() kernel-doc** said every FID is resolved through
   the mount and that lfs pairs them with lfsp_fsname; both wrong. Now:
   at 68288 "an MDT object is named from a map ... and is not looked up";
   at LU-20722 "only what the map cannot place is looked up, and only
   while that MDT is in service" (a separate fixup, so each commit reads
   right at its own place).

### 68288 #4, 10fe4e1b20: one finding (fixed, not rerun)
`llapi_scan_rec_path()` kept only CLS_OST_OBJ away from the lookup. With
LLAPI_SCAN_F_INTERNAL an OST's O/<seq>/LAST_ID is CLS_INTERNAL, its FID
passes `fid_is_sane()`, and the lookup goes to the scanned OST and waits.
lfs is safe (`find_rec_may_have_name()` checks first), but the public
function and its EXAMPLES are not. Fixed: any record with a class other
than CLS_VISIBLE and no owner returns -ENOENT with no lookup, which is the
same rule as `find_rec_may_have_name()`. The man page -ENOENT entry says
so. Real defect by reading; not reproduced (needs an OST image and a
stopped OST behind a mount).

## Verification (final tip b8c7d9c5b8)

- Build sweep `../a-0925/sweep.sh fb5ef60405 r0926b-tip`: **23/23
  clean**, `SWEEP fb5ef60405..b8c7d9c5b8` (`sweep-final.log`). Partial
  sweeps after each 68288 fold: `sweep-c.log`, `sweep-d.log`,
  `sweep-e.log`, each 18/18.
- checkpatch, old vs new, every commit whose tree changed: same findings,
  except two line lengths I added (an 86-column man `.TP` tag and an
  84-column comment), both fixed. The man-page part of checkpatch reads
  the work-tree file, so its lines show the tip whatever the commit.
- groff -ww: lfs-find.1 (one warning, upstream, line 1332 `\n` in an
  example, from 5bb91eaff0) and llapi_scan_rec_path.3 clean.
- Local A/B on this host, image `mdt.img` (one file with names f0 and
  hardlink under ROOT, one file solo), plugin built from the tree:
  hardlink table above; `--target MGS` -> "'MGS' is not an MDT or an
  OST", rc=22 (was "no target 'MGS' mounted here", rc=19); `--target
  testfs-MDT0000` still "no target ... mounted here" (conf-sanity 13585
  greps it); `--local --ost 0 --paths` -> refusal, rc=22; `--ls` on a
  device unchanged (documented).
- Own diff re-read after each fold.
- **Not verified on a live system:** the `--local --fid2path` filter
  (both forms) and the CLS_INTERNAL change. Both need the VM.

## Deferred

- 68288: `sd_` prefix rename (style).
- 68160: skip OSTs in a sweep for layout options (suggestion) — user's call.
- VM check of `--local --fid2path` (path and bare fsname) with targets of
  two filesystems, and llapi_scan_rec_path() on a CLS_INTERNAL OST record.
