# Decomposing OI Scrub — What the 105k Proxy Was Actually Measuring

**Date:** 2026-08-07
**Question:** K4 — can the in-kernel OSD path reach 1M objects/sec/MDT? The
2026-08-06 benchmark measured OI Scrub (the Option 2 stand-in) at 105k obj/s
against the device scanner's 705k and concluded "not today." That number was
a *proxy* with acknowledged bias in both directions, and it was never
decomposed. This run decomposes it, on both backends, with `perf`.

**Method:** same GCP labs as the verification runs (c3-standard-8). MDTs
scaled to ~2M objects (`createmany`). Full scrub via
`lctl lfsck_start -t scrub -r`, timed cold and warm; then re-run under
`perf record -a -g`, with per-symbol shares renormalized *within the
`OI_scrub` kernel thread* (`--comms OI_scrub --percentage relative`).

## ldiskfs: the 105k was two different limits wearing one number

| Scrub, 2,001,121 objects | run_time | rate |
|---|---|---|
| cold (after `drop_caches`) | 12 s | ~167k obj/s |
| warm | 4 s | **~500k obj/s** |

Cold scrub at 167k obj/s ≈ 2 GB of inode table at the pd-balanced streaming
rate — **cold scrub on this box is I/O-bound**, just like the device
scanner's cold pass (184k obj/s on the same device). The K4 benchmark's 105k
on the local VM was that box's ceiling; it does not transfer as a universal
"kernel path" constant. (At 301k objects the same scrub did 150–300k/s;
run_time is reported in whole seconds, hence the range.)

Warm — the per-object CPU cost, which is what K4 is really about — the
profile splits cleanly at the top of `osd_inode_iteration` (100% of thread
samples):

| Branch | share | what it is | LFU |
|---|---|---|---|
| `osd_scrub_next` → `osd_iit_iget` | **46.5%** | enumeration, `osd_iget` (25.8%), LMA read via `osd_scrub_get_fid`/`osd_get_lma` (26.4/18.1%) | **inherits** |
| `osd_scrub_exec` → `osd_scrub_check_update` | **53.1%** | OI lookup + verification: `__osd_oi_lookup`/`osd_oi_iam_lookup` 30.5%, the `iam_*` machinery | **drops** |

Hot flat symbols: spinlock pair ~22%, `find_inode_fast` 9.7% (icache hash),
`__find_get_block` 8.3% (buffer cache), `memcmp` 6.3% (iam key compares),
`osd_iget2` 3.2%.

**The K4 consequence:** 500k obj/s ÷ 0.465 ≈ **~1.05M obj/s** for a kernel
iterator that does only what LFU needs — enumeration + iget + LMA — on one
thread, on this CPU, metadata warm. The 1M objects/sec target is not
comfortably cleared, but it is *at the line* rather than 10× away, which is
what the raw 105k proxy implied on the old hardware. Attribute capture
beyond the LMA (the `rec()` extension payload) spends from this same budget,
so the margin is thin, not fictional.

## ZFS: the owed OI Scrub number

| Scrub, 2,001,121 objects | run_time | rate |
|---|---|---|
| first pass | 22 s | **~91k obj/s** |
| repeat (warm) | 23 s | ~87k obj/s |

Two facts, both rhyming with the userspace scanner:

1. **Warm equals cold** — the in-kernel ZFS path is CPU-bound, exactly as
   libzpool was. Flat profile: `mutex_lock` 12.3%, `_raw_spin_lock` 10.4%,
   `mutex_unlock` 6.0%, `zrl_add/remove`, `dbuf_hold/rele` — the same
   hold/lock traffic that capped the userspace scanner, now in kernel dress.
2. **In-kernel buys nothing on ZFS**: scrub's 91k obj/s sits between the
   userspace scanner's `-j 1` (87.6k) and nothing else. At one thread, the
   cost *is* the ZFS object machinery, not the address space.

Decomposition (children %, within the `OI_scrub` thread):

| Branch | share | what it is | LFU |
|---|---|---|---|
| `osd_scrub_next` | **65.3%** | `dmu_object_next` 22.3%, `dnode_hold_impl` 21.2%, LMA via `__osd_xattr_load_by_oid` 36.8% (incl. `nvlist_unpack` 11.1%) | **inherits** |
| `osd_scrub_check_update` → `osd_fid_lookup` | **34.1%** | OI verification: `zap_lookup_by_dnode` 27.8% (the OI on ZFS is a ZAP) | **drops** |

Ceiling arithmetic: 91k ÷ 0.653 ≈ **~140k obj/s** for a single-threaded
in-kernel ZFS iterator doing only LFU's work. Note the contrast with
userspace: there, the LMA `nvlist_unpack` measured 0.0% because libzpool's
userland allocator made it free; in-kernel it is a visible 11%, inside a
36.8% xattr-load branch. The kernel path pays *more* for attributes on ZFS,
not less.

## What this does to the Option 2 sequencing argument

1. **The 6.7× gap was partly hardware.** On equal cloud hardware, cold
   scrub and the cold device scanner are both device-limited (~167k vs
   ~184k obj/s). The device scanner's advantage is real but it is
   an *I/O-path* advantage (sequential table streaming vs itable walk with
   icache/buffer-cache traffic), not a 6.7× CPU advantage.
2. **Half of scrub's CPU is work LFU doesn't do.** The often-quoted "kernel
   iterator is slow" number includes OI verification that a scanner would
   skip. The iterator half alone extrapolates to ~1M obj/s single-threaded.
3. **The singleton still binds.** ~1M obj/s is a *single-thread* number and
   the otable iterator is one-per-device. The userspace scanners went 3.4×
   (ZFS) and hit the measurement floor (ldiskfs) by adding workers; Option 2
   has no equivalent lever unless per-object work is fanned out behind the
   single enumerator. That fan-out question is now the sharpest open item in
   the Option 2 design.
4. **The `rec()` attribute budget is quantified.** LMA-via-xattr is already
   ~18–26% of the thread in the inherited half on ldiskfs, and 36.8% on ZFS;
   each additional attribute fetched per object eats directly into the
   ceiling. Grounds for keeping `rec()`'s attribute set minimal and letting
   the fan-out layer do tier-2 work.
5. **Option 2's K4 answer is backend-asymmetric.** ldiskfs: the LFU-relevant
   kernel path extrapolates to ~1.05M obj/s — the target is reachable
   single-threaded. ZFS: ~140k obj/s, capped by the same DMU hold/lock
   machinery in kernel as in userspace, so on ZFS *neither* address space
   reaches the target without parallelism — and the userspace scanner
   already has parallelism (274k at `-j 24`) while the in-kernel singleton
   does not. Blunt version: **on ZFS today, the userspace device scanner is
   the faster path; Option 2's case there rests on liveness and WBCFS, not
   speed — unless the fan-out-behind-the-enumerator design lands.**

## Step 1 measured — the extrapolations are now superseded

The ceiling arithmetic above (÷ inherit-share) turned out to need direct
measurement, and the road there produced a finding of its own:

**`lctl lfsck_start -t scrub` does not measure the iterator.** The LFSCK
framework is the otable iterator's *consumer*, and the scrub producer paces
itself to LFSCK's window (`osd_scrub_next`: `wait_var_event` when
`!os_full_speed && !osd_scrub_has_window`). Proof: with the `lfu_noverify`
knob active on ZFS (OI verification verifiably gone — `zap_lookup` 0.0% in
the profile), scrub wall time stayed 22→23 s and the scrub thread measured
**0% CPU**, parked in `osd_scrub_next`. Every scrub-based wall-clock number
in this project — including K4's original 105k — was a *pipeline* number
bounded by the LFSCK engine, not an iterator number. (ldiskfs's pipeline is
not consumer-bound the same way: there, `noverify` did move scrub from 5 s
to 3 s.)

The correct harness is `src/kernel/lfu_it.c`: a one-shot module that is the
consumer LFU would be — `dt_locate` the otable object,
`do_index_try(dt_otable_features)`, then a tight `rec()`/`next()` loop
discarding FIDs. Producer + trivial consumer = the Option 2 pipeline floor.
Results at 2M objects, warm, single-threaded, `lfu_noverify` toggling the
producer's OI verification:

| backend | verify ON | **verify OFF (the LFU configuration)** | gain |
|---|---|---|---|
| ldiskfs | 415k obj/s (4.82 s) | **832k obj/s (2.40 s)** | 2.0× |
| ZFS | 106k obj/s (18.8 s) | **132k obj/s (15.1 s)** | 1.25× |

Repeat runs within 1%.

**The ZFS column is FID-only.** `DOIF_ATTR` is ldiskfs-only (step 3 scoped
ZFS out, per step 2), so the 132k figure excludes attribute capture, while
the userspace ZFS scanner's 87.6k includes ten SA lookups per object plus
classification. The two are therefore *not* comparable as they stand, and
the in-kernel number's apparent lead is unequal work — plus a kernel ARC
pre-warmed by the mount, where libzpool's starts cold each invocation.
Settling it needs `DOIF_ATTR` for osd-zfs and a re-run.

**K4, measured:** the in-kernel Option 2 pipeline floor is **832k obj/s on
ldiskfs** — short of the 1M target but within 20%, versus the 10× shortfall
the old proxy implied; the 1.05M extrapolation was ~25% optimistic (consumer
loop + residual scrub machinery). On ZFS it is **132k obj/s** (the 140k
extrapolation was close), still 2× behind the userspace scanner's `-j 24`.
Attribute capture beyond the FID will spend from these budgets.

Method note for everything that follows: module-only iteration on a mounted
system is `cp` the `.ko` + `depmod` — full `make install` fails on busy
`/sbin/mount.lustre`, and the failure is easy to miss (the first ZFS
"noverify" run silently measured an unpatched module; the `modinfo` parm
check is now part of the procedure).

## Step 2 measured — fan-out behind the singleton

`src/kernel/lfu_fanout.c`: the enumerator thread owns the iterator
(`lfu_noverify` on) and pushes `(oid, fid)` into a kfifo ring; N workers pop
and do the full naive per-object read — `dt_locate()` + `dt_attr_get()` +
`dt_xattr_get(trusted.lma)` — then drop the object.  The `dt_locate`
re-read is deliberately the waste the `rec()` extension would remove.
2M objects, warm; `located == produced, missing = 0` in every attrs run.

| workers | ldiskfs (obj/s) | ZFS (obj/s) |
|---|---|---|
| 0 (enumerate only) | 835k / 829k | 132k / 133k |
| 1, full attrs | — | 119k / 118k |
| 2, full attrs | **983k / 885k** | **133k / 133k** |
| 4, full attrs | 355k / 347k | 95k / 94k |
| 8, full attrs | 131k / 133k | 47k / 48k |
| control: 4 workers, attrs=0 | 246k | 72k |

Three conclusions:

1. **ldiskfs: the fan-out works.**  Two workers fully absorb the naive
   per-object attribute read while the pipeline holds ~900k obj/s —
   essentially the enumerator's own rate, *including* the `dt_locate`
   re-read tax.  Option 2's speed story on ldiskfs is funded: enumeration at
   ~832k, attributes hidden behind it, and the `rec()` extension buys margin
   rather than viability.
2. **ZFS: the enumerator is the wall, and it is inherent.**  Fan-out at best
   breaks even (w=2 exactly matches w=0's 132k; w=1 slightly loses).  The
   producer cannot be relieved of its per-object cost because **on osd-zfs
   the FID lives in the LMA** — `osd_scrub_next` must do the dnode hold and
   xattr load just to produce the FID.  Workers can only add work, not
   remove it.  With the userspace scanner at 274k (`-j 24`), **the ZFS
   posture is settled: Option 2 on ZFS is for liveness and WBCFS, not
   speed.**

   > **Reversed 2026-08-15** (`parallel-osd-measured-2026-08-15.md` §6a).
   > Fan-out could not move the ZFS enumerator, but *sharding* it can: with
   > `DOIF_PARALLEL` private iterators the in-kernel path reaches **561k
   > obj/s at 16 threads (3.64x the singleton's 154k)**, against the
   > userspace scanner's **220k** best measured on the same lab and pool.
   > The producer's per-object cost is indeed inherent — but it is spread
   > across per-dnode/per-dbuf locks rather than one global lock, so it
   > parallelises. On ZFS the in-kernel scanner is now the faster path by
   > ~2x, cold and warm.
3. **The ≥4-worker collapse is the harness ring, not the OSD** — proven by
   the attrs=0 control rows (4 idle workers are slower than 2 busy ones on
   both backends).  Per-entry kfifo pops under one spinlock with per-entry
   wakeups; `ofd_access_log.c` batches for exactly this reason, and the
   production ring must too.

## Step 3 measured — the `rec()` attribute extension, prototyped

`patches/rec-attr-v2_17_55.patch` (153 lines, ldiskfs + dt layer only):

- `DOIF_ATTR` iterator-init flag; `DORA_ATTR` rec bit;
  `struct dt_otable_rec { lu_fid; lu_attr }` in `dt_object.h`.  Additive:
  `attr == 0` keeps the bare-FID contract, LFSCK passes 0 and is untouched.
- Capture at `osd_iit_iget()` — the inode is in hand — into a parallel
  `ooc_attr[]` beside the otable cache (64 × `lu_attr` ≈ 8 KB per iterator;
  the widely-shared `osd_idmap_cache` is not enlarged).
- `osd_otable_it_rec()` honors its previously-ignored `attr` argument.

Measured (2M objects, warm, `noverify` on, same boot):

| rec() mode | rate | attrs returned |
|---|---|---|
| bare FID | 781k obj/s | — |
| **`DORA_ATTR`** | **793k obj/s** | **2,001,122 / 2,001,122 valid** |

**Attribute capture at the iterator is free** — within run-to-run noise of
the FID-only rate (the ±1.5% is smaller than boot-to-boot variance; the
832k step-1 figure was a different boot).  Full tier-0 attributes for every
object, one thread, no `dt_locate` re-read, no object-cache churn — what
the fan-out needed two workers to achieve.  ZFS is deliberately out of
scope for v1: step 2 showed the osd-zfs producer's per-object cost is
inherent (FID lives in the LMA), so there is nothing for this extension to
save there.

Combined Option 2 speed picture on ldiskfs, all measured on one lab:
enumeration 832k · +attrs via rec() ~793k (−5%) · fan-out available for
tier-2 work at ~900k with 2 workers.  The 1M objects/sec target is within
reach of known engineering (batched ring, capture tuning), and every claim
in the eventual Gerrit submission has a number behind it.

## Step 4 measured — the ring, and Option 2 as an actual scanner

`src/kernel/lfu_ring.c` + `src/kernel/lfu_ring.h` + `src/lfu_scan_kmdt.c`:
a misc chardev whose enumerator kthread owns the iterator (`DOIF_ATTR` on)
and streams 88-byte wire records through an SPSC ring — **stall-never-drop**
(the correction to `ofd_access_log`'s semantics the design demanded) with
**batched wakeups** every 2048 records (the step-2 lesson).  Userspace side
is the third `lfu_target_ops` backend: ~200 lines, no device libraries,
classification/filters/output from the common core.

Measured on the ldiskfs lab, 2M objects, **MDT mounted and serving**:

| | |
|---|---|
| end-to-end rate | **795,866 obj/s** (2,001,122 records, 2.51 s; repeat 795,728) |
| vs in-kernel `rec()` discard loop | 793k — **the ring + copy_to_user + userspace core cost ~0** |
| FID-set diff vs the device scanner (same MDT, unmounted) | **identical: 2,001,034 visible both sides, 0 only-kmdt, 0 only-dev** |

That diff is the strongest correctness statement in this project so far:
Option 1 and Option 2 enumerate the same namespace through entirely
different stacks — libext2fs on the raw device vs the OSD iterator on the
mounted target — and agree exactly, object for object.

Option 2 is no longer a harness: enumerate → attributes → ring → userspace
classify/filter/emit is the scanner, at ~796k obj/s on a live MDT.

Remaining before it is *the* scanner rather than a prototype: LMA
compat/incompat flags in `dt_otable_rec` and the wire record (classification
currently FID-sequence-only — invisible on this namespace, not in general);
multi-target support and a start/stop interface instead of one module param;
foreground-impact measurement under client load; and the upstream
conversation for the `rec()` extension, now with every number attached.

## Caveats

- Cloud VM, loop/file-backed targets, page-cache-warm for the CPU numbers;
  absolute rates are not server-class claims. The *decomposition shares*
  are the transferable result.
- Scrub in "no repairs needed" mode (`updated: 0, failed: 0` throughout);
  a scrub finding inconsistencies would spend more in the droppable half.
- `perf` children-percentages overlap across branches (`iam_` totals 65.8%
  by symbol-prefix because iam functions appear under both branches'
  callchains); the 46.5/53.1 top-level branch split is the reliable figure.
- Whole-second `run_time` granularity: 4 s at 2M could be anywhere in
  ~445–570k obj/s; "500k" is the midpoint reading.
