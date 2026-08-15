# DOIF_ATTR for osd-zfs — attribute capture at the otable iterator

**Date:** 2026-08-08
**Patch:** `patches/rec-attr-zfs-v2_17_55.patch` (applies on top of
`patches/rec-attr-v2_17_55.patch`, which carries the shared `dt_object.h`
hunk: `DOIF_ATTR`, `DORA_ATTR`, `struct dt_otable_rec`)
**Base:** `v2_17_55-22-g61b1dc9d13`
**Status:** **compiled and measured 2026-08-10** — see
[`rec-attr-zfs-measured-2026-08-10.md`](rec-attr-zfs-measured-2026-08-10.md).
It built clean on the first attempt and holds the iterator's rate with 100%
attribute capture (110,463 vs 109,270 obj/s bare-FID, same boot, 2M objects).
This document is the design rationale; the numbers below marked "expected" have
been superseded by that one.

## Why this, and not the other route

There are two ways to get attributes for an object the iterator hands you:

**Route A — FID → attrs, a genuine random lookup.** What `dt_locate()` +
`dt_attr_get()` does, i.e. what `src/kernel/lfu_fanout.c` workers did:

1. `osd_fid_lookup()` (`osd_oi.c:658`) — hash the FID to an OI ZAP, `zap_lookup()` → dnode number
2. `__osd_obj2dnode()` (`osd_object.c:259`) → `dnode_hold()`
3. `osd_sa_handle_get()` (`osd_internal.h:903`) → `sa_handle_get_from_db()`
4. `__osd_object_attr_get()` (`osd_object.c:167`) → `sa_bulk_lookup()` of 10 `SA_ZPL_*` + `osd_xattr_get_lma()`
5. `osd_attr_get()` (`osd_object.c:932`) → `sa_object_size()`, and `zap_count()` for directories

That is an OI ZAP lookup **plus** a second dnode hold per object, on top of
what the enumerator already paid. It is why ZFS fan-out broke even at 132k
obj/s (see `docs/scrub-decomposition-2026-08-07.md`).

**Route B — capture alongside the FID.** On osd-zfs the FID lives in the LMA,
so `osd_otable_it_next()` (`osd_scrub.c:1682`) *already* holds a dnode, a bonus
buffer and an SA handle for every object it returns — and then throws the
handle away:

```c
rc = __osd_xattr_load_by_oid(dev, it->ooi_pos, &nvbuf);   /* osd_index.c:195 */
    dmu_bonus_hold(...);
    sa_handle_get_from_db(...);
    __osd_xattr_load(osd, hdl, sa);   /* DXATTR nvlist -> LMA -> FID */
    sa_handle_destroy(hdl);           /* <-- discarded here */
```

The attributes are one `sa_bulk_lookup()` away on a handle that is already
open. Route B is implemented.

## What the patch does

| File | Change |
|---|---|
| `osd_index.c` | Split `__osd_xattr_load_by_oid()` into `__osd_xattr_load_by_oid_keep()`, which returns the SA handle to the caller instead of destroying it. The old entry point becomes a two-line wrapper — no behaviour change for its five existing callers. |
| `osd_internal.h` | `struct osd_otable_it` gains `struct lu_attr ooi_attr` and `ooi_want_attr:1`. osd-zfs's iterator is single-slot, so no array is needed (osd-ldiskfs needed `ooc_attr[OSD_OTABLE_IT_CACHE_SIZE]`). |
| `osd_scrub.c` | New `osd_otable_it_attr()`; `DOIF_ATTR` decoded in `osd_otable_it_init()`; capture in `osd_otable_it_next()`; `osd_otable_it_rec()` honours `DORA_ATTR`. |

`osd_scrub_next()` — the scrub thread's own producer path — is deliberately
untouched. OI scrub does not want attributes, and leaving it alone keeps the
patch off the hot path of the only in-tree consumer.

## Deliberate divergences from `osd_attr_get()`

- **No `zap_count()` for directory `la_size`.** `osd_attr_get()` replaces a
  directory's size with `512 * blocks` and counts the ZAP; that is a full ZAP
  walk per directory. The iterator leaves the SA size in place and does not set
  `la_dirent_count`. A consumer needing exact directory sizes must fall back to
  `dt_attr_get()` for directories.
- **LMA flags come free.** `__osd_object_attr_get()` re-reads the LMA xattr to
  derive `LUSTRE_ORPHAN_FL` / `LUSTRE_ENCRYPT_FL`. `it::next` already has the
  swabbed LMA in hand, so `lma_to_lustre_flags(lma->lma_incompat)` is folded in
  with no I/O.
- **`la_rdev` is not fetched.** `osd_attr_get()` does an extra `sa_lookup()` for
  char/block devices. Not useful to a namespace scanner; skipped.

`sa_object_size()` on the open handle is kept — it is cheap and gives
`la_blocks`/`la_blksize`.

## Userspace side: nothing to do

`src/kernel/lfu_ring.c` already passes `LFU_DOIF_ATTR` unconditionally at
`otable_it_init()` and calls `iops->rec(..., DORA_ATTR)`. The flag was a no-op
on osd-zfs and the bare-FID branch was taken; with this patch the same binary
starts receiving attributes. `lfu_scan_kmdt.c` needs no change either.

One consequence worth noting: `lfu_scan_kmdt.c` currently derives
`have_lma = (rec.fid.f_seq != 0)` because LMA flags are not on the wire. That
stays true — this patch puts `lu_attr` on the wire, not `lma_incompat` — except
that the orphan/encrypt bits now arrive folded into `la_flags`, which is a
partial answer to the same gap.

## Expected result — and what was actually measured

The prediction, written before any of this compiled: the enumerator is already
forced to pay the dnode hold, bonus hold and SA handle to produce the FID at
all, so adding a `sa_bulk_lookup()` on that open handle is the same shape as
the measured ldiskfs result (793k obj/s with 100% attribute capture vs 781k
bare-FID on the same boot), and ZFS should hold its rate.

**Confirmed 2026-08-10** on a rebuilt lab, 2M objects, same boot, alternating
passes: **110,463 obj/s with 100% attribute capture vs 109,270 obj/s
bare-FID** — the with-attributes arm marginally ahead, i.e. free within noise.
Full run in
[`rec-attr-zfs-measured-2026-08-10.md`](rec-attr-zfs-measured-2026-08-10.md).

Two things the prediction got wrong, both about context rather than the patch:

- The absolute rate is **109k on that lab, not the 132k** measured on the
  deleted one at the same object count. Cross-lab rates do not transfer; only
  same-boot pairs do.
- The like-for-like margin over Option 1 is therefore **1.27×** (110.5k vs
  87.2k), not the 1.5× the old unfair pairing implied.

The ZFS posture is unchanged, as predicted: the otable iterator is a per-device
singleton, fan-out behind it breaks even, and userspace `-j 24` at 275k obj/s
still wins by 2.5×. Option 2 on ZFS remains a liveness/WBCFS argument.

## Build notes from the first compile

It built clean on the first attempt — neither anticipated issue (`ARRAY_SIZE`
sign-compare on `cnt`, `ZFS_DEFAULT_PROJID` visibility under a
non-`ZFS_PROJINHERIT` build) materialised, and `osd-zfs` produced no warnings.
Gate any future run on the module actually being the new one before believing a
number:

```bash
nm lustre/osd-zfs/osd_zfs.ko | grep -E "osd_otable_it_attr|__osd_xattr_load_by_oid_keep"
modinfo src/kernel/lfu_it.ko | grep recattr
```
