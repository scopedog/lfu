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
