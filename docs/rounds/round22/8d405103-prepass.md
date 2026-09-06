# 68288 `8d405103`: the directory pass no longer opens the target twice

Deferred on 2026-09-04 with a reason, and picked up now on the user's word.

## What was actually wrong

Two things, and only one of them was the "defect" the comment led with.

The **premise** — that an MDT can build an empty map, so the OST refusal fires
on an MDT with no directories — was disproved on 2026-09-04 by building that
filesystem: a real MDT always carries ~116 directories of its own (`ROOT`,
`O/`, `REMOTE_PARENT_DIR` and the rest of the OSD's tree), so `dm_used` is
never 0 on one.

The **secondary point stood**, and is what this fixes: the map was built by a
scan of its own, so `--fid2path` and `--paths` opened the target twice — and
on an OST the second open read a single object and threw the map away. On ZFS
an open is a pool import and a close a `spa_export()` plus `kernel_fini()`.

And the test *was* asking the wrong question, even where the answer came out
right: "the map is empty" is a fact about the answer, where "this is an OST"
is a fact about the target, and `llapi_scan_tgt.tt_flags` has carried that
since the backend opened it.

## The fix

- `scan_device_sweep()` — one sweep of every chunk — lifted out of
  `scan_device_run()`, which now calls it. The cursor, the stop value and the
  per-worker counters reset there, so a second sweep starts clean.
- `struct scan_prepass` and `scan_device_run_prepass()`: a sweep to run
  before the caller's own, **on the same open and the same workers**.
  `pp_tgt_flags` says which targets it is for and `pp_missing_rc` what a
  target without them is — 0 to skip the pre-pass, or the error the call
  fails with. `scan_device_run()` stays as it was, a wrapper passing NULL, so
  no earlier patch in the series has to change.
- `scan_dirmap_build()` becomes `scan_dirmap_prepass()`: it sets up the map
  and describes the pass, and no longer runs one. `llapi_find_device()` hands
  it to the scan.
- The refusal is now the pre-pass's: `--paths` sets `pp_missing_rc` to
  `-ENOTDIR`, so a target that is not an MDT is refused **from its label,
  before either sweep runs**. `--fid2path` sets 0 and simply gets no
  pre-pass on an OST, naming those objects through the mount as it always did.

## Measured

    lfind --device /tmp/lustre-mdt1 --paths -type f     opens of the target: 2
    lfind --device /tmp/lustre-mdt1 -type f             opens of the target: 2

`--paths` now costs a search's own opens and nothing more (the ldiskfs backend
opens the target once and once per worker). Before, it was that twice over.

Everything else on a fixture built for it — a 2-stripe directory with eight
files, scanned offline:

- `llapi_scan_device_test`: **7 of 7 pass**, including the thread-count
  equivalence and the consumer-stop cases the sweep refactor could have broken
- `--paths` composes the real pathnames (`/shardtest/f1` and its siblings)
- `--paths` on an OST is refused with the same message as before
- **`conf-sanity 165` PASS ×2** — the subtest whose whole subject is lfind over
  a scanned MDT

**A fixture trap, again**: the first re-check after the rename ran against loop
files `conf-sanity` had reformatted and left empty, and reported two failures
that were nothing to do with the code. Rebuilt the fixture, all seven pass. An
arm whose fixture changed under it proves nothing — see the standing note.

## Verification

Amended into 68288 (`e7880257c7` -> `ebf4ac92aa`); `range-diff` shows that
commit alone changed, the eight above it identical. 20 commits, 20 Change-Ids,
the commit and the tip build, checkpatch warnings unchanged (the three new
checks are `== NULL` house style the file already uses throughout).
