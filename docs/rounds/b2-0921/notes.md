# Batch 2, 2026-09-21 — 68288, 68415, 68416

Re-cut from the original (68288, 68726, 68727), which was not pushable: a
stacked push has to be contiguous and 68726/68727 sit above the changelog
series. Only 68288 was worked today.

## The ten open threads: all already addressed

Same as batch 1. 68288's reported defect — the dirmap gate keyed on
`dm_used != 0` — was real in PS14 and the tree already reads
`dm_used != 0 || param->fp_paths`; its man page names the ownerless OST
object; its message is reflowed; and the `LLAPI_SCAN_*` bits are dense again
(1<<32 … 1<<52, no holes). 68727's five are all in the tree. 68726 had none.
The `fsname[MAX_OBD_NAME + 1]` item belongs to LU-20650, not here.

## lreview on 68288, first run: 7 findings, no defects

Taken, as [`b2fix.py`](b2fix.py):

1. **The dirmap is handed over when the pre-pass *ran*, not when it *found*
   something.** The code's own comment says "the map is used whenever it was
   built"; the `dm_used` test contradicted it for an MDT whose files all sit
   in the filesystem root, and `--fid2path` then fell through to one
   `llapi_fid2path_at()` per object against the target being scanned.
   `struct scan_prepass` gains `pp_ran`, set where the pre-pass sweeps —
   the same correction `scan_device_run_prepass()` already made one level
   down, whose comment calls the old way "a test on the answer where the
   question is about the target".
2. `--paths` and `--fid2path` refused together in the library, not only in
   `lfs`.
3. The man page sentence claiming every match prints as a FID.
4. Two EXAMPLES lines for the new options.

**Rejected:** the `-Waddress-of-packed-member` claim — `ff_parent` is at
offset 0, and compiling the file with `-Wall -Wextra` produces no such
warning. The reviewer reasoned from the `packed` attribute rather than the
offset. **Queued to 68160** (already pushed): skipping OSTs in the `--local`
sweep when `--paths` is set.

Verified: 26/26 per-commit builds; three lab checks in
[`b2paths.sh`](b2paths.sh) — `--paths` output unchanged, a plain device scan
unchanged, an OST still refuses `--paths` identically. The fix's *intended*
difference needs an MDT with an empty map and a surviving mount, a DNE shape
this rig cannot build cheaply, so it is argued from the code and measured
only for non-regression.

## lreview after the fixes: 6 findings, no defects

Full text in [`lreview-68288-after-fixes.txt`](lreview-68288-after-fixes.txt).
**Nothing taken tonight.** The first one is a question about the fix itself
and is the one to settle tomorrow:

1. **Is skipping the lookup right for `--fid2path` specifically?** `--paths`
   has nothing else to try, but `--fid2path` was handed a live mount, and a
   lookup through *that* never touches the target being scanned. Under DNE
   the loss is real: scanning MDT1 of a filesystem rooted on MDT0, a remote
   directory's linkea parent is not in MDT1's map, so it and everything below
   it is counted nameless — exactly the names the mount could have produced.
   Either fall back to `llapi_scan_rec_path()` on a map miss when
   `fc_mnt_fd >= 0`, or say in lfs-find.1 that `--fid2path` names no more
   than `--paths` on an MDT.
2. `sd_want` is never narrowed by the `known` mask the pre-pass already
   computes from the label, so on ZFS every MDT object pays a `zap_lookup()`
   for `trusted.fid` that can only return ENOENT. `dev.sd_want &= known`
   before recomputing `sd_want_xattr` would close it and drop the MDT-only
   xattrs on an OST too.
3. Declarations after a statement in the `pp_ran` block (style).
4. The pre-pass's want does not go through `scan_want_widen()`.
5. `strncpy()` into `sd_name[NAME_MAX + 1]` NUL-pads 256 bytes per insert —
   ~256MB of memset on a million-directory MDT, paid again per rehash;
   `strscpy()` would drop it.
6. A `.TP` without `15` and an escaped dash in llapi_scan_device.3.

Items 2 and 5 are performance on paths this project cares about; they want
measuring, not just fixing.
