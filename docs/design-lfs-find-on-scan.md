# `lfs find` on the scanner API — the split (LU-20605)

**Date:** 2026-08-18 · **Revised:** 2026-08-25, to match the landed code ·
**Depends on:** LU-20603 (the scan record) ·
**Ticket text:** [`tickets/lfs-find-on-llapi-scan.md`](tickets/lfs-find-on-llapi-scan.md)

How `lfs find` was rebuilt on the scanner's record without changing what it
prints. §1 was written before the patch, from a read of `cb_find_init()`
(`lustre/utils/liblustreapi_pfind.c:2419-3000` at `4322543e7e`); §2 and §5 have
been rewritten against what shipped.

## 1. What `cb_find_init()` actually does

Eight phases, and the order is the performance model:

| # | phase | I/O |
|---|---|---|
| 1 | cheap pre-filters: depth, `--name` via `fnmatch`, `-type` from `d_type` | none |
| 2 | decide whether MDT info is needed at all (`decision = 0` if any predicate wants it) | none |
| 3 | gather from the MDT: `get_lmd_info_fd()` → statx + LOV; `cb_get_dirstripe()` → LMV for directories; MDT index | one ioctl, two for dirs |
| 4 | filter on MDT values: perm, type, uuid, foreign, stripe\*, layout, comp, mirror, pool, projid, times (`for_mds`), btime, attrs | none |
| 5 | gather again, only for survivors that still need size / blocks / nlink: `fstatat(p, de->d_name)` — the **glimpse** | one stat, OSTs involved |
| 6 | filter on stat values: times (`for_mds=0`), `--newerXY`, size, blocks | none |
| 7 | print: skip-percent sampling, then `printf_format_string()` or the path | — |
| 8 | `decided:` depth bookkeeping, return 1 at `fp_max_depth` | — |

**Gather is interleaved with filter, twice**, and the cheap filters run before
any ioctl. `lfs find --name '*.log'` today performs no ioctl on a non-matching
name. That is the same tier model LFU built for the device scanners, and it is
load-bearing: any split that gathers everything first makes `--name` an
ioctl-per-object scan.

## 2. The split — as landed

> **Revised 2026-08-25 to match the code.** §2 and §5 described a plan that was
> not what shipped: `llapi_find()` was *not* re-hosted on
> `llapi_scan_namespace()`. The goal — one implementation of find's predicates,
> several sources of objects — was reached by splitting the deciding half out
> of `cb_find_init()` instead. §1, §3 and §4 stand as written. Code below is
> `../lustre-lu20603` @ `1e706d95f9`.

### 2.1 Why not `llapi_scan_namespace()`

`llapi_scan_namespace()` has no traversal of its own. It ends at
`llapi_find_with_cb(buf, &param, llapi_scan_cb_init, cb_common_fini)`
(`liblustreapi_scan.c:575`) — the same walk `llapi_find()` uses, with a
different callback. The two callbacks are siblings, not layers:

```
llapi_find_with_cb()  ->  parallel_find() / param_callback()
      |- cb_find_init()        <- lfs find
      \- llapi_scan_cb_init()  <- llapi_scan_namespace()
```

Routing `llapi_find()` through `llapi_scan_namespace()` would re-enter that
walk one level down and materialise a record per object on the way, to share a
traversal both callbacks already share. Two things also do not fit:

- **Gather shape.** `llapi_scan_cb_init()` gathers once, from `ss_want`, then
  delivers. `cb_find_init()` gathers twice by design — the MDT ioctl at phase
  3, filter, then the glimpse on survivors at phase 5. The generic record has
  no phase-5 hook; adding one would exist only for find.
- **Find-only state.** `gather_all` for `-printf`, the per-invocation
  `fp_get_lmv` reset, the depth bookkeeping at `decided:`, and presenting the
  record as an `lmd` for the printing path.

### 2.2 What shipped instead

`cb_find_init()` keeps its place as the traversal callback and is rebuilt
around the record in situ (`liblustreapi_pfind.c:3565`):

```
cb_find_init(path, p, dp, param, de)
  scan_rec_dirent(&rec, path, p, d, de)     -- phase 1 input, shared
  find_prefilter(&rec, param, &checked_type)-- phase 1
  want = find_want(param, checked_type, gather_all)  -- phase 2
  scan_rec_gather(param, path, p, &d, &fd, want, &rec)  -- phase 3, shared
  find_decide(&fc, param)                   -- phases 4-7, behind struct find_ctx
  decided:                                  -- phase 8
```

`scan_rec_dirent()` and `scan_rec_gather()` (`liblustreapi_scan.c:53`, `:287`)
are the same functions `llapi_scan_cb_init()` calls. So `lfs find` does run on
the record and on the scanner's gather — it just enters the walk at the same
level `llapi_scan_namespace()` does, rather than underneath it.

`struct find_ctx` (`:2525`) is what carries the deciding half's inputs, and it
is the piece that made the second consumer possible: `fc_path == NULL` means no
namespace was walked, `fc_p`/`fc_d`/`fc_fdp` are `-1`/`NULL` when there are no
descriptors, and `fc_mnt_fd` is a client mount to resolve a FID against or `-1`
to print the FID.

### 2.3 The second consumer

`llapi_find_device()` (`:3465`) runs the same predicates over
`llapi_scan_device()` — *"the objects come from `llapi_scan_device()` instead
of a namespace walk, so this reads a target directly and does not need it
mounted, or its server running, or a client anywhere."* Three consequences it
handles rather than hides:

- **It prints FIDs.** A target holds names and parent FIDs, not paths;
  `fc_mnt_fd` turns them into pathnames when a mount is available.
- **A predicate answerable only in the mounted filesystem is refused before
  the scan starts** (`find_device_supported()`), rather than silently matching
  nothing.
- **A scan cannot glimpse**, so `fp_lazy` is forced for the duration and
  `trusted.som` is the only answer a size can have.

That is the debt argument settled: one set of predicates, two sources of
objects, and `lfind(8)` is the third caller on top.

## 3. What this forced into the API (folded into LU-20603 before push)

Three things the record as first written could not do. All are additive.

1. **A demand mask, `sp_want`.** Phase 2 in the consumer's terms: the
   `LLAPI_SCAN_*` bits it needs. `0` means everything. If nothing beyond the
   dirent is wanted, the scanner performs no ioctl. Same idea as
   `lfu_filter_needs()`.
2. **A pre-filter, `sp_filter`.** Called before any I/O with a record that
   carries only path, name and the `d_type`-derived type (`LLAPI_SCAN_TYPE`).
   Return 0 to gather and deliver, 1 to skip this object without gathering it
   (descent is unaffected), negative to stop. Phase 1 lives here.
3. **What phases 5 and 7 need from the record.**
   - `sr_parent_fd` and `sr_fd`, so the glimpse is `fstatat(parent, name)`
     exactly as upstream does it, not `lstat(path)`.
   - LMV for directories, `sr_lmv`/`sr_lmvsize` with `LLAPI_SCAN_LMV`, since
     `--mdt-count`, `--hash-type`, `--foreign` and the nlink rule all read it.
   - `LLAPI_SCAN_LAZY_SIZE` / `LAZY_BLOCKS`: `OBD_MD_FLLAZYSIZE` says the value
     in `sr_size_bytes` is a lazy one, which is what `--lazy` consumes. This is
     the size finding from the LU-20603 lab, made usable.

`sp_want` and `sp_filter` are `llapi_scan_namespace()`'s spelling of phases 2
and 1. `lfs find` reaches the same two phases through `find_want()` and
`find_prefilter()` directly (§2.2), so these remain the API's, not find's —
but they were designed by asking what find needed, which is what the exercise
was for.

## 4. Where the risk is

Not a crash. A subtle change in which objects match for one flag combination.
The corners: `--lazy`, `--newerXY` (two passes over times, `for_mds` then
stat), skip-percent sampling, `-printf` format strings, and the striped-
directory nlink rule. `sanity.sh` 56\* covers a lot of this and not all of it;
anything it does not cover gets a targeted before/after on the lab.

## 5. Order of work — as landed

Four changes, stacked, plus the `lfind(8)` utility:

| | Change | Proof |
|---|---|---|
| 1 | `llapi: split the deciding half out of cb_find_init` — the checks, the glimpse and the printing behind `struct find_ctx` | `sanity` 56\* |
| 2 | `lfs: share find's predicate parsing` — the option table, its loop and thirteen argument helpers into `lfs_find_parse.c`, compiled into both `lfs` and `lfind` | `sanity` 56\* |
| 3 | `llapi: run find's predicates over a device scan` — `llapi_find_device()`: the record as an `lmd`, the LMV conversion, the size rule | conf-sanity test_165 |
| 4 | `utils: lfind, find over a scan of a target` — `lfind(8)`, its three target spellings, the man page | conf-sanity test_165 |

`llapi_find()` still calls `llapi_find_with_cb(path, param, cb_find_init,
cb_common_fini)` (`liblustreapi.c:3468`), and `cb_find_init()` stays exported
for the callers that pass it explicitly. The walk and the gather order are
byte-identical to before the split, which is what makes `sanity.sh` 56\* a
usable oracle for a change whose stated risk (§4) is a silent difference in
which objects match.
