# `lfs find` on the scanner API — the split (LU-20605)

**Date:** 2026-08-18 · **Depends on:** LU-20603 (`llapi_scan_namespace()`) ·
**Ticket text:** [`tickets/lfs-find-on-llapi-scan.md`](tickets/lfs-find-on-llapi-scan.md)

Plan of record for rebuilding `lfs find` on the scanner API without changing
what it prints. Written before the patch, from a read of `cb_find_init()`
(`lustre/utils/liblustreapi_pfind.c:2419-3000` at `4322543e7e`).

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

## 2. The split

**Reimplement `llapi_find()` on `llapi_scan_namespace()`, and leave `lfs.c`
alone.** `lfs find` keeps calling `llapi_find()`; underneath, phases 1–3 and 8
belong to the scanner and phases 4–7 become the consumer callback.

```
llapi_find(path, param)
  └─ llapi_scan_namespace(path, &sp, find_consume, param)
        sp.sp_want   = what param's predicates need (from phase 2's test)
        sp.sp_filter = find_prefilter          -- phase 1, on the dirent
        find_consume(rec, param)               -- phases 4-7 on the record
```

Why here and not in `lfs.c`: LU-20605's purpose is to prove the record is
sufficient for a real consumer, and that is proved just as well one layer down
— with a diff confined to `liblustreapi_pfind.c`, `sanity.sh` 56\* still an
oracle, and no library logic dragged into a utility.

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

## 4. Where the risk is

Not a crash. A subtle change in which objects match for one flag combination.
The corners: `--lazy`, `--newerXY` (two passes over times, `for_mds` then
stat), skip-percent sampling, `-printf` format strings, and the striped-
directory nlink rule. `sanity.sh` 56\* covers a lot of this and not all of it;
anything it does not cover gets a targeted before/after on the lab.

## 5. Order of work

1. Fold §3 into LU-20603, rerun the lab's seven checks plus two new ones
   (`sp_want` skips the ioctl; `sp_filter` skips objects).
2. `find_prefilter()` and `find_consume()` in `liblustreapi_pfind.c`, moving
   phases out of `cb_find_init()` rather than copying them.
3. `llapi_find()` over the scanner. `cb_find_init()` stays exported for the
   `llapi_find_with_cb()` callers that pass it explicitly.
4. `sanity.sh` 56\* on the lab, before and after, diffed.
