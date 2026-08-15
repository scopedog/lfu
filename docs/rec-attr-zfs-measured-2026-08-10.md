# DOIF_ATTR on osd-zfs — compiled, and the ZFS row made like-for-like

**Date:** 2026-08-10
**Patch:** `patches/rec-attr-zfs-v2_17_55.patch` on top of
`patches/rec-attr-v2_17_55.patch`, base `v2_17_55-22-g61b1dc9d13`
**Status:** **compiled and measured.** The "never compiled" caveat in
`docs/rec-attr-zfs-2026-08-08.md` is closed.

The question this run answers: the design record compared Option 1's ZFS
scanner at 87.6k obj/s (ten SA attribute lookups per object) against Option 2's
in-kernel iterator at 132k obj/s (bare FID, no attribute capture), on different
namespace sizes. That is not a comparison. This run puts both scanners on the
**same MDT, same namespace, same boot, both reading full attributes**.

---

## 1. The lab

| | |
|---|---|
| Instance | GCP `lustre-zfs-lab`, `c3-standard-8`, 100 GB pd-balanced, `us-central1-b` |
| OS | Rocky Linux 9.8, kernel `5.14.0-687.36.1.el9_8` |
| OpenZFS | 2.2.10 (DKMS), userland and kmod at the same version |
| Lustre | `v2_17_55-22-g61b1dc9d13` + both rec-attr patches, `--enable-server --with-zfs --disable-ldiskfs` |
| Filesystem | `FSTYPE=zfs MDSSIZE=16777216 bash llmount.sh`, loopback vdev `/tmp/lustre-mdt1` |
| Namespace | `createmany -m`, 4 × 500,000 → **2,000,333 objects** (~7,000 creates/s) |

Same recipe as the 2026-08-07 lab except the object count, which was raised
from 301k to 2M to match the in-kernel baseline's namespace.

**The patch compiled clean on the first attempt** — no warnings from
`osd-zfs`, and both new symbols are in the module:

```
000000000002e8b0 t osd_otable_it_attr
0000000000027e70 T __osd_xattr_load_by_oid_keep
```

Neither anticipated first-build issue (the `ARRAY_SIZE` sign-compare, the
`ZFS_DEFAULT_PROJID` visibility under a non-`ZFS_PROJINHERIT` build) actually
materialised.

---

## 2. Attribute capture is free on osd-zfs, as it is on ldiskfs

`lfu_it.ko` alternating `recattr=0` / `recattr=1` on one boot, MDT mounted,
ARC warm, single-threaded, 2,000,096 objects returned by the iterator:

| pass | `recattr` | time | obj/s | `attr_ok` |
|---|---|---|---|---|
| warm-up | 0 | — | — | — |
| 1 | 0 | 18.286 s | 109,378 | 0 |
| 2 | 0 | 18.136 s | 110,283 | 0 |
| 3 | **1** | 18.043 s | **110,851** | 2,000,096 |
| 4 | 0 | 18.505 s | 108,084 | 0 |
| 5 | **1** | 18.204 s | **109,871** | 2,000,096 |
| 6 | 0 | 18.293 s | 109,336 | 0 |
| 7 | **1** | 18.073 s | **110,667** | 2,000,096 |

**Bare FID 109,270 obj/s · with attributes 110,463 obj/s** (means). The
with-attributes arm is 1.1% *faster*, i.e. the difference is noise: attribute
capture at the iterator costs nothing measurable. `attr_ok` counts records
whose returned `la_mode` is non-zero — **100% capture, 2,000,096 of
2,000,096**.

This is the same result as ldiskfs (793k with attrs vs 781k bare on one boot),
and for the same reason: `osd_otable_it_next()` already holds the dnode, the
bonus buffer and an SA handle to read the LMA, so `sa_bulk_lookup()` on that
open handle adds no I/O and no second hold.

A second boot (pools exported and re-imported, MDT remounted) reproduces it:
bare FID 104,627 obj/s, with attributes 106,935 obj/s.

---

## 3. The like-for-like row

Same MDT, same 2M namespace. Option 1 needs the pool exported, Option 2 needs
it mounted, so the two arms are consecutive rather than simultaneous; the ARC
is dropped between them by the export.

| | Option 1 · userspace device scanner | Option 2 · in-kernel OSD scanner |
|---|---|---|
| target state | exported (unmounted) | mounted and serving |
| **1 thread, full attributes, warm** | **87,174 obj/s** | **110,463 obj/s** |
| 1 thread, bare FID | n/a (always reads attrs) | 109,270 obj/s |
| 1 thread, cold | 85,631 obj/s | 64,774 obj/s |
| parallel | **275,157 obj/s** (`-j 24`) | 107,181 obj/s end-to-end; fan-out gives nothing |
| visible objects | 2,000,009 | 2,000,009 |

Userspace detail (each run is its own process, so libzpool's ARC starts empty
every time; `-q`, live exported dataset):

| `-j` | cache | time | obj/s |
|---|---|---|---|
| 1 | cold (`drop_caches`) | 23.36 s | 85,631 |
| 1 | warm | 22.93 / 22.61 / 23.31 s | 87,237 / 88,471 / 85,814 |
| 24 | warm | 7.23 / 7.31 s | 276,671 / 273,643 |

87.2k at `-j 1` and 275k at `-j 24` reproduce the 2026-08-07 lab's 87.6k and
274k almost exactly, on a 6.6× larger namespace and a different VM — so
Option 1's ZFS numbers are stable, and the two labs are comparable.

Both arms read the same attribute set: the userspace scanner does ten
`SA_ZPL_*` lookups plus `sa_object_size()`; `osd_otable_it_attr()` does the
same ten in one `sa_bulk_lookup()` plus `sa_object_size()`. The in-kernel arm
additionally gets the LMA flags for free (it has the swabbed LMA in hand) and
deliberately skips the `zap_count()` directory-size walk that `osd_attr_get()`
does — see the 08-08 design note.

### What the fair comparison changes

- **Option 2 is faster single-threaded, by 1.27×** — not "likely close", which
  is what the design record guessed when it could only note the row was
  unfair. The reason is that Option 2's per-object cost is one dnode hold
  and Option 1 pays the same hold from userspace with a colder, process-local
  ARC.
- **It is a smaller win than the unfair row suggested.** The old 132k-vs-87.6k
  pairing implied 1.5×; the real like-for-like margin on this lab is 1.27×.
- **The ZFS posture does not change.** The otable iterator is a per-device
  singleton and fan-out behind it breaks even, so Option 2's ceiling is ~110k;
  Option 1 at `-j 24` is 275k, still **2.5× faster overall**. Option 2 on ZFS
  remains a liveness/WBCFS argument.
- **Cold flips the single-thread row.** With caches dropped, Option 1 loses 2%
  (85.6k) and Option 2 loses 41% (64.8k). The userspace scanner's chunked
  parallel reader tolerates a cold cache far better than the singleton
  iterator does — worth remembering, because a production MDT scan is a cold
  scan.

### Absolute rates differ from the deleted lab

This lab's in-kernel bare-FID rate is 109k obj/s where the 2026-08-07 lab
measured 132k on the same 2M object count. Different VM instance, different
kernel build (`687.36.1` vs `687.34.1`), and this namespace was built with
`createmany -m` (no LOV xattr on the objects). The **same-boot pair** is what
carries — every conclusion above rests on arms measured against each other,
never across labs. Option 1's arm reproducing 87.6k → 87.2k across the two
labs suggests the difference is on the kernel side.

---

## 4. The ring works on osd-zfs unmodified

`lfu_ring.ko` + `lfu-scan-kmdt`, MDT mounted and serving, no source change —
as the 08-08 note predicted, the module already passed `LFU_DOIF_ATTR`
unconditionally and the flag simply stopped being a no-op:

```
stream complete in 18.66s (live MDT via lfu_ring)
  records seen  : 2000096      visible : 2000009      internal : 87
  rate          : 107,181 objects/sec
```

Two runs: 107,181 and 108,133 obj/s, against the in-kernel iterator's ~107k on
that boot. **Ring, copy and userspace consumer cost ≈ 0 on ZFS**, the same
result as ldiskfs (796k end-to-end vs 793k in-kernel).

And a cross-stack correctness check falls out of it: the ring stream and the
userspace device scanner — disjoint code paths, one on a mounted target and
one on an exported one — both report **2,000,009 visible objects**.

---

## 5. What is still open

- `perf` decomposition of the in-kernel path on this lab (why 109k here and
  132k on the previous one).
- The cold in-kernel result (64.8k) is one measurement, taken on the first
  pass after a fresh import, so it also carries Lustre mount warm-up. It wants
  a repeat before it is quoted as a cold *steady-state* number.
- Everything in the 08-08 note's open list: OST-side scanning, LMA flags on
  the wire, `traverse_dataset()` prefetch, DNE, encrypted datasets.
