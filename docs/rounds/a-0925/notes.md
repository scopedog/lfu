# 2026-09-25: the three AI PS27 findings, fixed locally (no push)

Work tree `~/lfs-artem-0924`, branch `artem-0924`. Backup of the tip before
this round: `backup/artem-0924-pre-0925` (= `923eb412cb`). New tip
**`6a243dd557`**, tag `r0925-tip`. 26 commits, the same Change-Ids. 68094
(`f42d20f639`) and 68095 (`d2a385f08f`) are unchanged, as the freeze
requires.

The change is defined by four transforms in this directory, applied in
order to the old tip: `xform.py` (the three findings), `xform2.py`
(checkpatch line wraps), `xform3.py` (lreview 68156), `xform4.py` +
`msg4.py` (lreview 68163). Result: `diff -r` against the new tip is empty.
Each pass was a `rebase -i` with an `exec` step after every pick
(`step*.sh`). Conflict stops (68159 and 68288, where the stack adds lines
next to the removed fields) were resolved by taking the commit's own file
and running the transform again, then `--continue` with no amend.

## 1. 68156: a device scan fills rdev and blksize -- FIXED, with a twist

**The AI's premise is wrong.** It said the walk reports 10:200 for
`mknod c 10 200`. Measured on the clone VM (2.17.57, 2-MDT ldiskfs):

| node | stat(2) on a client | walk (ll_dir_ioctl) | device scan, old | device scan, new |
|---|---|---|---|---|
| c 10 200 | 10:200 | **0:2760** | 0:0 | 10:200 |
| b 8 1 | 8:1 | 0:2049 | 0:0 | 8:1 |
| c 300 5 | 44:5 | 0:11269 | 0:0 | 44:5 |
| c 4 1048000 | 253:192 | 0:64960 | 0:0 | 253:192 |

Why: `ll_mknod()` sends `old_encode_dev(rdev)`, the MDT stores that number
as `la_rdev`, and ext4 writes it as a new-style dev (debugfs: `00:ac8`).
`ll_update_inode()` decodes it with `old_decode_dev()`, which is why stat is
right. `ll_dir_ioctl()` does `MAJOR()`/`MINOR()` on the encoded number and
does not decode it: **an upstream llite bug**, not ours. The client also
truncates majors and minors above 255 (c 300 5 becomes 44:5).

So the fix makes the device scan report what `stat(2)` shows, not what the
walk shows. The AI's literal suggestion (decode i_block[] as ext4_iget does)
would have copied the walk's wrong 0:2760.

- `struct llapi_scan_obj` gains `so_rdev`: the OSD's `la_rdev`, filling the
  4-byte hole after `so_gen` (no ABI release yet, so no bump).
- ldiskfs backend: decode i_block[0] (old) or i_block[1] (new) as
  `ext4_iget()` does. That gives `la_rdev`.
- ZFS backend (68163): `ZPL_RDEV`, which osd-zfs stores as `la_rdev`.
- core `scan_rec_obj()`: `old_decode_dev()` into `stx_rdev_major/minor` for
  CHR/BLK; `stx_blksize = getpagesize()`, as `ll_dir_ioctl()` sets PAGE_SIZE.
- `llapi_scan_device.3`: one paragraph.

Not covered: the scan of a target in service (LU-20720/20722). `struct
lfu_rec` carries no rdev, so it still reports 0:0. That is a wire-format
change, left for the 2.19 series.

**Upstream bug to file (ask first):** `ll_dir_ioctl()` in
`lustre/llite/dir.c` (~2480) should use `old_decode_dev(body->mbo_rdev)`,
as `ll_update_inode()` does. Once fixed, the walk and the device scan
agree.

Lab (`lab0925.sh`, `zlab0925.sh`, `rdevdump.c`), old arm = `lab0924-new`
(a0924-pushed), new arm = `lab0925-new`. The lab was built from the
first-pass tree; later passes changed only line wraps, man pages, one
error message and one comment.
- ldiskfs: 11/11 PASS. The new arm matches stat on all four nodes,
  blksize 4096. The old arm reads 0:0. Walk records are identical old vs
  new. `find --projid 1999` and `-printf %LP` are identical old vs new, on
  the walk and on the device scan. `-type c` gives the same 3 objects.
- ZFS (2.2.11, stopped fs, pools exported, `--search /tmp`): 6/6 PASS.
  10:200, 8:1, 253:192. The old arm reads 0:0. `-type c` is old = new.

## 2. 68157: the message -- FIXED

"The first changes what -printf prints:" is now "The first changes what
-printf prints; the second is documentation:".

## 3. 68157: fc_projid / fc_have_projid dropped -- FIXED

The AI's claim was checked first and holds. `find_want()` clears
`LLAPI_SCAN_PROJID` unconditionally, `scan_rec_dirent()` memsets the walk's
record, and `scan_rec_gather*` sets the bit only when `want` has it. So on a
walk `lfsr_valid & LLAPI_SCAN_PROJID` is 0, which is what `fc_have_projid`
was. `find_get_projid()` and the `-printf` gate read `fc->fc_rec`. The three
copies in `find_device_cb()` (68159), `find_since_rec_cb()` and
`find_changelog_rec_cb()` (LU-20650) are gone. Every `find_ctx` sets
`fc_rec` before `find_decide()`. Lab: see 1, `--projid` and `%LP` are
unchanged.

## Verification

- Build sweep (`sweep.sh b7b1332a42 artem-0924`): 26/26 clean. It covers
  utils, the public header, the three scan test programs, and both backends
  at -O2 -Werror.
- checkpatch at baseline on every changed commit. 68156 first rose 4 -> 6
  (two long lines); xform2 wrapped them back to 4.
- Change-Ids identical to before; 26 commits.

## lreview (one commit at a time)

- **68156** (`da6d50bc87`): 2 low.
  1. [x] `llapi_scan_namespace.3` -EINVAL did not cover `LLAPI_SCAN_F_INTERNAL`,
     which the walk refuses on purpose (one flag mask per scanner). The man
     page now says so (xform3; only where the flag exists, so 68094 is
     untouched).
  2. [-] The comment missing HSM in `LLAPI_SCAN_WANT_MDT_ONLY` is already
     fixed higher in the stack, by LU-20637 (68288).
- **68157** (`61bf69abba`): clean.
- **68163** (`14bf9863d8`): 2 low.
  1. [x] The ZFS backend's -ENOPKG (pool features libzpool lacks) printed
     "needs Lustre's e2fsprogs". It now prints "unsupported pool features;
     needs newer libzpool", and the kernel-doc names both libraries. No test
     greps either string.
  2. [x] The message and one comment described the patch's history. Four
     sentences and the `scan_backend_kind()` comment are now stated as facts
     about the code. Small edits, not a rewrite.
- Not lreviewed, named: 68159, LU-20650 x2, LU-20722 (the changes there only
  delete lines or shift context), and 68163 after its two lreview fixes
  (small, compiled, checkpatch at baseline).

## Still owed

- Gerrit: nothing. The replies were posted and resolved on 09-25. The push
  waits for the user (freeze: minor findings are not a reason to refresh).
- The ll_dir_ioctl rdev ticket (above), with the user's OK.
- 68160's commit message: the `-f`/`--foreign` line (09-25 memory), not in
  this round.

## 68416: AI review on PS16 (09-25 afternoon) -- 4 fixed, 1 declined

Tip before: `6a243dd557` (`r0925-tip`), backup `backup/artem-0924-pre-0925b`.
**New tip `78a5c837d2`** (tag `r0925b-tip`). All changes are in 68416
("LU-20650 llapi: fill a scan record for one FID") and carried up.

- 7d4bc57c lustreapi.h: "validated as they are for the other two" ->
  "validated as llapi_scan_device() validates them" (lfsp_flags is checked
  against LLAPI_SCAN_F_KNOWN_DEV, so F_INTERNAL is accepted here).
- aad80829 llapi_scan_test.c: <libgen.h> moved after <getopt.h>. LU-20603
  ("pull a scan's records in batches") already had that order; its
  conflict was resolved by taking its own file, which is exact.
- 7a5777eb liblustreapi_scan.c: "llapi_scan_ device()" and the
  "lfsr_parent_fd is / -1 for a directory" wraps fixed.
- d885e5c4 liblustreapi_scan.c: the O_DIRECTORY open after the statx maps
  -ENOTDIR to -ESTALE (a directory replaced by a non-directory). The man
  page's -ESTALE ("the name ... holds a different object now") and the
  kernel-doc already cover it; no doc change. Proven with the real arm
  lifted into `enotdir-harness.c` (statx a dir, replace it with a file,
  open): old rc=-20 (ENOTDIR), new rc=-116 (ESTALE).
- [-] 0344623c (fold the lfsp_got hunk into 68159): declined again, as on
  09-24 -- it cuts through 7 commits and the gap is llapi-caller-only.

lreview of 68416 (`lreview/lr-68416.log`, 2 minor, both fixed):
- lfsp_got's kernel-doc had lost "a bit ... is dropped rather than
  refused", which lustreapi_internal.h's "see lfsp_got in lustreapi.h"
  still points at. Sentence restored.
- @mnt_fd said "an open descriptor on a client mount"; it must be the
  mount root (-EXDEV otherwise). Now "the root of a client mount".

Checks:
- Tree: every commit from 68416 up differs from the old tip by exactly the
  same hunks (plus the include order from 68416 to below LU-20603).
- Build sweep of the 16 changed commits (`sweep.sh artem-0924~16`): 16/16
  clean, on `932d456a5f`. The final tip differs from that at every level
  in comment lines only, so the sweep stands.
- checkpatch on 68416: 0 errors, 1 warning (baseline; one pass had an
  81-column comment, shortened).
- Change-Ids unchanged; 26 commits; 68094/68095 untouched.

Not done: no Gerrit replies (rule: the reply goes with the push).

## 68163 AI PS24 (3ca6a2f2): osd-zfs xattr storage objects -- FIXED

Tip **`58b9bf3708`** (tag `r0925c-tip`), from `78a5c837d2`; backup
`backup/artem-0924-pre-0925c`. 68163 is now `ef5906ea85`. The bottom seven
commits (68094 ... 68160) are unchanged. Every commit from 68163 up differs
from its old version by the same 46 lines (libscan_zfs.c +35/-1,
conf-sanity.sh +10/-2).

The AI's premise was half right. osd-zfs keeps an xattr that does not fit
the 64 KB SA (DXATTR_MAX_SA_SIZE) in a directory of its own, one object per
value, and both reach the scan. But they do not land in NO_LMA, and they are
not listed under --internal: they have no ZPL_MODE, so they were counted in
**ss_skipped** (SKIP_INVALID). `lfs find --device` then warned "7 of 339
objects were skipped: unreadable or inconsistent on the target" on a healthy
MDT. A single 40 KB value fits the SA and makes no extra object (measured).

What they look like (debug plugin on the VM, 2.2.11):
- the xattr dir: DMU_OT_DIRECTORY_CONTENTS, SA bonus never written (header
  magic 0). __osd_xattr_set() creates it with __osd_zap_create() and never
  calls __osd_attr_init().
- each value: DMU_OT_PLAIN_FILE_CONTENTS (UINT8_METADATA for a local FID),
  SA holds only ZPL_SIZE; LINKS, PARENT and GEN answer ENOENT.

Fix: both are dropped before any sink call, as the ldiskfs backend drops an
ea_inode, so they are not counted anywhere. The dir test is on the bonus
header, before sa_handle_get(). The value test runs only on the path where
ZPL_MODE is missing, so the normal path costs nothing. Any other object
without a mode is still SKIP_INVALID. One paragraph added to the message.

Lab (`zxab0925.sh`, `statdump.c`; clone VM, 1 MDT zfs, stopped, pools
exported): 3 files hold 7 xattr objects (two with 2x40 KB, one with 3x40
KB), plus a 61-component PFL file and a char device. 8/8 PASS:
old skipped=7, new skipped=0; new sees exactly 7 fewer; every class count
identical (NO_LMA 230 on both); --internal emitted and no-FID records
identical; `lfs find --device -printf` records identical; the false
"skipped" warning is gone. Each arm run twice, alternated, same fixture.

Lab trap, new: this `lab0925-new` liblustreapi has no PLUGIN_DIR, so it
dlopens `$LUSTRE/utils/scan_osd_zfs.so`. A bind mount on
/usr/lib64/lustre does nothing for it. The first A/B showed no difference
for that reason. `zlab0925.sh` was still right (each arm had its own
LUSTRE). The A/B now copies each plugin into its own `$LUSTRE/utils`.

lreview of 68163 (`lreview/lr-68163c.log`): 1 minor, fixed. conf-sanity
300's OST half errored on ENOTSUP for a ZFS OST in a build without the ZFS
backend, while the MDT half skips. It now prints "not scanning ost1: no zfs
scan backend" and goes on. It does not skip, because the MDT half has
already run. Error text now "scanning DEV failed", as the MDT half's.
bash -n at all 19 commits; not run on a mixed ldiskfs-MDT/ZFS-OST cluster.

Build sweep `10d2193daa..` 19/19 clean (utils, header, tests, both backends
-O2 -Werror) on the tree before the conf-sanity edits; libscan_zfs.c is
unchanged since. checkpatch on 68163 at baseline (2 warnings, as before).

## ll_dir_ioctl rdev: reproduced (09-25 evening)

The user asked to run it on the VM. Clone VM, 2.17.57 ldiskfs (tree
`~/lustre-0918`, `d749df6ca9f`), 2 MDTs + 1 OST, llmount.sh loads the
tree's modules. A = stock `lustre.ko` (srcversion `6AF1556074C69F944F10FAA`),
B = the same tree with `old_decode_dev()` in the V2 arm of `dir.c`
(srcversion `1EAEDFDD3B6DC43AAFFECDB`). Arms alternated A B A B, each a full
cleanup + rmmod + remount (NOFORMAT after the first), and each arm checks
`/sys/module/lustre/srcversion`. `rdevab.sh`, `getinfo.c`.

`getinfo` calls `IOC_MDC_GETFILEINFO_V1` and `_V2` on the parent directory
with the name, as llapi does. (A first run used `LL_IOC_MDC_GETINFO_*`,
which answers for the directory itself, and read 0 for everything. That
run is discarded.)

| node | stat(2), ls -l | V1 st_rdev -> major():minor() | V2 in A | V2 in B |
|---|---|---|---|---|
| c 10 200 | 10:200 | 0xac8 -> 10:200 | **0:2760** | 10:200 |
| b 8 1 | 8:1 | 0x801 -> 8:1 | **0:2049** | 8:1 |
| c 300 5 | 44:5 | 0x2c05 -> 44:5 | **0:11269** | 44:5 |
| c 4 1048000 | 253:192 | 0xfdc0 -> 253:192 | **0:64960** | 253:192 |

Both A runs and both B runs are identical. **The bug reproduces and the
one-line fix works.** V2 now matches stat(2) on every node.

**V1 is correct, not by luck of layout:** it copies the raw old-encoded
value into `st_rdev`, and glibc's `major()`/`minor()` read bits 8-19 and
0-7 plus the high bits, which for a value below 0x10000 are exactly the old
encoding's two bytes. The old encoding holds only 8+8 bits, so V1, V2 fixed
and stat(2) all show the same truncated numbers (c 300 5 -> 44:5). That
truncation is the wire format (`mbo_rdev` is 32 bits, old-encoded by
`ll_mknod()`), not this bug.

No userspace tool in master prints the V2 rdev: `lfs find` has no rdev
`-printf` field, and `liblustreapi_pfind.c:251` only fills it from lstat()
on the fallback path. So the impact on master is llapi callers of
`llapi_get_lmd_info*()`/GETFILEINFO_V2, and our `llapi_scan_namespace()`.
No sanity subtest in the draft for that reason: it would need a new C
helper, and `lustre/tests/statx.c` uses the statx syscall, not the ioctl.
Worth adding if a reviewer asks; `getinfo.c` is the helper.

**Draft patch** (NOT pushed, no ticket): `llite-rdev-draft.patch`, commit
`f0bf053fba` "LU-XXXXX llite: decode rdev for GETFILEINFO_V2" on master
`550451c0e4`, in the session scratch clone. One local `dev_t rdev =
old_decode_dev(body->mbo_rdev)`, used by both MAJOR() and MINOR().
checkpatch: 0 errors, 0 warnings. The draft's form (local variable) was
also compiled on the VM tree: clean. The lab's B arm had the same decode
inline. `--no-verify` only because the hook refuses LU-XXXXX; with a real
ticket the hook adds the Change-Id.

**Jira:** no existing ticket. Searched `stx_rdev` (0), `mbo_rdev` (LU-20779
interop 160a and LU-5954 GETFILEINFO ino: neither is about rdev),
`GETINFO_V2`/`GETFILEINFO_V2` + rdev (LU-14489, unrelated), `old_decode_dev`
(kernel updates, unrelated), summary ~ rdev (0).

VM state after: `~/lustre-0918/lustre/llite/dir.c` restored and rebuilt,
`lustre.ko` srcversion back to A, modules unloaded, lab files in
`~/rdevlab/`. VM shut down.

Owed: file the LU ticket and push the patch -- the user's call.
