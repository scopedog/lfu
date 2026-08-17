# Lustre's Own Suites Against the Patched osd-zfs

**Date:** 2026-08-17 (after
[`zfs-tier1-measured-2026-08-17.md`](zfs-tier1-measured-2026-08-17.md))
**Lab scripts:** [`tests/lab-zfs/`](../tests/lab-zfs/) — `10-suite.sh`,
`11-swap.sh`, `12-recheck.sh`
**Raw data:** [`bench-data/2026-08-17/zfs-suite-regression.txt`](../bench-data/2026-08-17/zfs-suite-regression.txt)

Every ZFS run so far tested the feature we *added*. This tests the code we
**touched**. `lustre/osd-zfs/osd_scrub.c` is the scrub's own file, and the patch
refactors `__osd_xattr_load_by_oid()` — which the normal scrub path calls for
every object, not only ours. A leaked or double-freed `sa_handle_t` there would
never show up in our own tests, because they only exercise the `DOIF_ATTR` path.

**Result: no regressions.** Patched and clean `v2_17_55` produce identical
results on all three suites, and the kernel log is clean on both.

---

## 1. The comparison

One box, one boot, module sets swapped between rounds (`11-swap.sh`), so the two
columns differ only in which `osd_zfs.ko` is installed.

| suite | patched | clean v2_17_55 |
|---|---|---|
| `sanity-scrub` (full) | **16 pass · 0 fail** · 26 skip | **16 pass · 0 fail** · 26 skip |
| `sanity` (`ONLY="24 27 33 39 102 103"`) | 128 pass · 4 fail · 50 skip | 128 pass · **4 fail** · 50 skip |
| `conf-sanity` (`ONLY="0 1 5 32"`) | **22 pass · 0 fail** · 2 skip | **22 pass · 0 fail** · 2 skip |
| `kernel BUG` / `WARNING:` / `Call Trace` / NULL deref | none | none |

`sanity-scrub` is the one that matters. It drives OI scrub end to end through
the iterator and the xattr-load path the patch touches, including **test 5**
(the scrub state machine) and **test 6** (resume from the last checkpoint, which
exercises the `store()`/`load()` position cookies our sharding reuses). If the
private-iterator changes had leaked into the singleton path, test 6 is what
would have caught it.

## 2. The four `sanity` failures are the lab, not Lustre and not us

They fail identically on both columns, which already excludes the patch. Two of
them were then fixed outright by a `chmod`:

| test | cause | after `chmod o+x $HOME` |
|---|---|---|
| `102c` | non-root `getfattr`/`setfattr` for `lustre.lov` | **PASS** |
| `102j` | non-root `tar` restore of stripe info | **PASS** |
| `27W` | `enable_setstripe_gid` | still fails — different cause, see below |
| `27Ke` | `enable_foreign_dir` | still fails — different cause, see below |

All four originally died as `execvp fails ... (13): Permission denied`. The
suites exec binaries out of the **build tree**, which here lives under
`/home/nishida` at mode `drwx------`, so every test that drops to `RUNAS_ID`
(uid 500) fails before reaching any Lustre code. Proof rather than inference: as
uid 500, `$LUSTRE/utils/lfs` is `Permission denied` while the installed
`/usr/bin/lfs` runs and prints `lfs 2.17.55_dirty`.

With the traverse bit set, `102c` and `102j` pass on **both** builds. The other
two get further and fail for reasons of their own, still identically on both:

- **`27W`** — the directory default is set with `lfs setstripe -C 4` (over*striping*,
  so two OSTs are not the obstacle). The file then created while
  `enable_setstripe_gid=0` comes back with **no layout at all** rather than
  inheriting that default, so the test's `((stripe_count == defcount))` has
  nothing to compare. Whether that is an upstream bug on osd-zfs or a
  configuration effect is **not established here**; it is only established that
  it predates our patch.
- **`27Ke`** — `create_foreign_dir` returns `Operation not permitted` when
  creating a foreign directory as uid 500. Same status: unexplained, and
  present without our patch.

## 3. What the run does not cover

- **`sanity` is a subset**, not the full suite: `ONLY="24 27 33 39 102 103"` —
  basic operations plus the xattr and ACL groups, chosen because the patch reads
  attributes and extended attributes. A full `sanity` run on ZFS is hours.
- **`conf-sanity` is four groups** (0, 1, 5, 32), covering mount, remount and the
  upgrade-image tests, not the whole suite.
- **`sanity-lfsck` was not run.** LFU/LFSCK coexistence was measured separately
  on ldiskfs (2026-08-15); the equivalent on ZFS is untested.
- **Single node, `MDSCOUNT=1`, `OSTCOUNT=2`.** Nothing here exercises multiple
  MDTs, failover, or recovery.

## 4. Two lab mistakes worth keeping

Both produced *plausible-looking* results rather than obvious failures, which is
the dangerous kind.

- **`make install` failed with `/sbin/mount.lustre: Device or resource busy`**
  because the filesystem was still mounted — while the *build* had succeeded. The
  script would have gone on to run the "baseline" suites against the **patched
  modules still on disk**, and the comparison would have come out identical for
  the wrong reason. `11-swap.sh` now tears the filesystem down first, refuses to
  continue if anything is still mounted, and verifies the **installed** module
  for `osd_otable_it_xattr` — failing loudly if it does not match the mode asked
  for.
- **`scp` over a script that bash is currently executing** corrupts the run: bash
  reads the file lazily by byte offset, so the baseline run ended in a syntax
  error inside an edit that landed mid-execution. The suites had already
  finished; only the epilogue broke. Copy to a new name, or wait.

A third, smaller: the dmesg check grepped `-i "BUG"`, and every test banner is a
`Lustre: DEBUG MARKER` line — `DEBUG` contains `BUG`, so the first run reported
the entire suite as alarming. It now matches `kernel BUG` and friends.
