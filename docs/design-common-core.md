# LFU Scanner Common Core — one scanner, N backends

**Date:** 2026-08-07 (implemented same day; see test results at bottom)
**Realizes:** design-zfs-scanner.md §3 ("one binary, two backends"), the
`lfu_target_ops` split both prototypes were written toward.

## What moved where

Both scanners were standalone binaries with deliberately parallel structure.
The refactor extracts that structure into a shared core; each backend keeps
only its device access.

| File | Owns |
|---|---|
| `src/lfu_scan.h` | `lfu_target_ops`, `lfu_rec`, `lfu_stats`, `lfu_opts`, `lfu_ctx` |
| `src/lfu_core.c` | §5 classification ladder · tier ordering · record emission · stats merge · §8 chunked worker pool · common CLI · per-backend capability refusal |
| `src/lfu_filter.h` | the compiled filter (`struct lfu_filter`, a fixed-size POD that is also the kernel ioctl payload), the record, the demand mask, and the evaluator's contract — dual-mode: kernel branch under `__KERNEL__` (`filter-levels.md`) |
| `src/lfu_filter.c` | the parser: lfs find syntax → `struct lfu_filter`; userspace only |
| `src/lfu_filter_eval.c` | the evaluator: tier-0/tier-1 evaluation, SOM/LOV/LMV/linkea decoders, `lfu_filter_validate()`; one source, linked here and `#include`d into `src/kernel/lfu_ring.c`, held to kernel constraints (no libc, no allocation, `gnu89`) in both |
| `src/lfu_scan_ldiskfs.c` | libext2fs open/scan, torn-read defence (§8.2), inode+LMA extraction, superblock banner, summary format |
| `src/lfu_scan_zfs.c` | libzpool import/open, SA registry, dnode read path, DXATTR/LMA unpack, summary format |
| `src/lfu_scan_kmdt.c` | the `lfu_ring` stream from a mounted MDT; compiles the filter and hands it to the kernel (`.pushdown`), which evaluates it before a record enters the ring; per-tier counts come back by ioctl |

Three backend binaries remain (`lfind-ldiskfs`, `lfind-zfs`, `lfind-kmdt`)
because the build hosts differ — MDS build hosts lack ZFS headers, and vice
versa.  **That is a packaging constraint and no longer reaches the command
line**: `lfind` (`src/lfind.c`) is the user-facing command, and it picks a
backend from the target and `exec`s it.

The choice is by what the target *is*, not by a required flag, because each
backend already takes a different kind of name: a block device or image is
ldiskfs, `pool/dataset[@snap]` is ZFS, a character device is the `lfu_ring`
stream from a mounted target.  The front-end deliberately does not parse the
filter vocabulary — duplicating that table would give it two places to drift —
so it finds the target by scanning arguments from the right in two passes: first
for one that really is a device, image or stream, then for one merely *shaped*
like a dataset spec.  The ordering matters: a `--name a/b` pattern does not
exist as a path and so looks exactly like a dataset, and without the two passes
`lfind <image> --name a/b` dispatches on the pattern.  `--backend
ldiskfs|zfs|kmdt` overrides all of it.

## The ops contract

Control is inverted relative to a `next()`/`read()` iterator API: the backend
loops over one *chunk* of its id space and calls the core per object —
`lfu_prefilter()` on tier-0 attributes, then `lfu_object()` once the LMA and
whatever xattrs the demand mask asked for are read.  The two enumeration styles
(libext2fs buffered inode scan; ZFS `dmu_object_next()`) are different enough
that a shared iterator signature made both worse.

The backend does not decide *which* xattrs to read: `cx->needs` carries the
compiled filter's demand mask, and the backend fetches exactly that set and
hands the raw values over as `struct lfu_eas` for the core to decode.  Fetching
is device-specific (`ext2fs_xattr_get()` vs `nvlist_lookup_byte_array()` against
an already-unpacked DXATTR); interpreting is Lustre, and identical on both, so
it lives in one place.  A backend also declares what it *cannot* answer —
`can_supply`, `attr_mask`, `missing_fields` — and the core refuses such a query
at parse time rather than letting a scan quietly test fewer predicates than were
asked for.  A backend that evaluates the whole filter itself (`pushdown`: the
kmdt stream, where the kernel does it) tells the core so, and the core neither
prefilters nor re-runs tier 1 on what it receives; the backend's verdict rides
in the record (`rec->unknown`) and its decoded tier-1 values in `rec->t1`.

The core hands out chunk indices from a shared cursor (not N equal slices —
allocation is sparse and clustered on both backends, so equal slices
imbalance badly).  This is the `-j` scan from the ZFS work, now common:

- **ZFS**: chunk = 64K object IDs; workers share the objset (DMU is
  thread-safe); end-of-table proved by a failed `dmu_object_next()`.
- **ldiskfs**: chunk = enough block groups to cover ~64K inodes; libext2fs is
  *not* thread-safe, so each worker opens its own read-only `ext2_filsys`
  (and its own inode bitmap) and positions a private scan with
  `ext2fs_inode_scan_goto_blockgroup()`; end-of-table known from
  `s_inodes_count`.

## Semantics: unified where safe, kept split where real

Unified (behavior changes, both deliberate):

- **Filter ordering** is now the ldiskfs rule everywhere: tier-0 predicates
  run *before* any xattr work, and filtered objects are never classified.
  On ZFS this means a filtered object no longer costs the DXATTR unpack —
  semantic parity with §7, though the unpack profiled at 0.0%.
- **`-i`** now means "also emit `internal`" on both (previously ldiskfs
  emitted every non-visible class).  OST/agent/bad emission can return as a
  separate flag if a consumer needs it.
- **`--limit`** now counts emitted records on both (previously ZFS counted
  dnodes seen) and forces `-j 1`.
- `-p` stays backend-local (ldiskfs: historical short for `--projid`;
  ZFS: `--search DIR`).  `--projid` is the common spelling.
- **The filter vocabulary is `lfs find`'s** (2026-08-17), because LFU replaces
  that command: `--atime +30d`, `--size +1G`, `--type f`, `!` for negation, and
  the rest.  `-a`, `-b` and `-p` are kept as aliases and compile to the same
  predicates — `-b` to `--dev-blocks`, which is what it always measured.

Kept split, because the difference is real and papering over it would lie:

- **Summary formats** — each suite parses its own; they also name genuinely
  different skip taxonomies (bitmap/dtime/csum/validate vs
  not-znode/sa_fail/no-dxattr).
- **`blocks` semantics** — post-compression physical on ZFS (§12, open).
- **`no-lma` / `links==0` meaning** — normal on osd-zfs, suspicious on
  ldiskfs (real-MDT finding, 2026-08-07).

## Build

```
make                                  # ldiskfs backend (needs libext2fs ≥1.47
                                      #   — Rocky stock 1.46.5 lacks
                                      #   ext2fs_xattrs_read_inode; the
                                      #   Lustre-patched e2fsprogs provides it)
make zfs [ZFS_SRC=/usr/src/zfs-X.Y.Z] # zfs backend (ZFS_SRC on RHEL/Rocky)
```

## Test status

- ldiskfs suite **17/17**, ZFS suite **16/16**, both on the workstation and
  on Rocky 9.8 (GCP).
- ZFS real-MDT regression: output **byte-identical** to the pre-refactor
  scan of `lustre-mdt1/mdt1@lfu1`; `-j` timings unchanged (3.34s / 1.35s /
  1.18s at `-j` 1/8/24 on the 301k snapshot).
- ldiskfs real-MDT (packaged Lustre 2.17.0 server, 301k files via
  `createmany`): oracle + `-j` identity + equal-parallelism throughput — see
  `docs/ldiskfs-mdt-parallel-2026-08-07.md`.

## Deployment note found on the way

Prebuilt `kmod-lustre-osd-ldiskfs-2.17.0-291.el9` requires a **RHEL 9.7
kernel** (kABI: `wbc_account_cgroup_owner` etc.); on a 9.8 userland install
the matching `5.14.0-611.20.1.el9_7` kernel from the Rocky vault, boot it,
then install the kmods.  Also: the `lustre` metapackage resolution drags in
`lustre-zfs-dkms` (broken without EPEL) — install `kmod-lustre*` +
`lustre-osd-ldiskfs-mount` first, then `lustre`, in separate transactions.
