# What the 512-byte record costs the device scanner — 2026-09-04

The statx switch grows `struct llapi_scan_rec` from **328 to 512 bytes**,
most of it `struct statx` padding we never read, and `scan_rec_obj()`
memsets one per object. The write-up said "not measured". This is the
measurement.

**Answer: about 2% of the device scanner's CPU time, ~8 ns per object.**
Two-thirds of that is literally the bigger memset.

## Setup

`rhel9.7-server-mgs-mds-clone`, AMD Ryzen 5800X (4 vCPU), ldiskfs.
A 3 GB MDT (1,199,984 inodes) populated with `createmany -m` —
mknod inodes, MDT-only, no OST objects — then unmounted, giving
**1,000,262 objects seen / 1,000,007 emitted**. Single-threaded
(`sp_thread_count = 1`), pinned to one CPU.

Two arms, each its own `liblustreapi.so` **and** its own harness compiled
against its own header, resolved by rpath: the record's size is a
compile-time constant on both sides of the callback, so an arm that mixes
them measures nothing.

## Result

| | pre (328 B) | post (512 B) | |
|---|---|---|---|
| warm CPU, min | 0.4242 s | 0.4344 s | +2.40% |
| warm CPU, median | 0.4320 s | 0.4405 s | +1.99% |
| cold-cache CPU, median | 0.6688 s | 0.6833 s | +2.17% |
| throughput, warm | 2.31 M obj/s | 2.27 M obj/s | |

Aggregate medians are not the headline, because a single arm's runs spread
**17–20%** on this VM. The estimate is the **paired** one — runs alternate
pre, post, pre, post, so each post has an adjacent pre that saw nearly the
same machine:

| | pairs | median | IQR | post slower | sign test |
|---|---|---|---|---|---|
| warm | 120 | **+1.84%**, +8.0 ns/obj | [+0.80, +2.81]% | 103/120 (86%) | p < 0.0001 |
| cold cache | 12 | **+1.85%**, +12.3 ns/obj | [+1.42, +2.19]% | 10/12 (83%) | p = 0.039 |

Four estimators — warm min, warm median, cold median, paired median — all
land between +1.8% and +2.4%. At 30 pairs they did not: median said
+1.17% and the sign test gave p = 0.099. The effect is real but small
enough to need ~100 pairs.

## Where it goes

`memset()` of 328 vs 512 bytes, a million times, measured on the same CPU:
**5.5 ns/object**. That is two-thirds of the +8.0 ns the scan actually
lost; the rest is the larger stack frame's cache footprint.

So it is the per-object `memset(rec, 0, sizeof(*rec))` in
`scan_rec_obj()`, and if it ever mattered it is recoverable — zero the
header and the fields actually filled rather than the whole record. Not
proposed now: 2% does not justify hand-maintained partial initialisation
of a public struct, which is exactly the kind of thing that later reads
back a stale field.

## Two ways this measurement could have lied, and did

1. **`rsync -a` preserves mtimes**, so after swapping the arm's sources
   `make` saw nothing newer than the objects built from the *other* arm
   and rebuilt nothing. Both arms ran the **same library**. Caught only
   because the harness sums `rec->sr_size` and both arms reported 328.
   A benchmark's first duty is to prove the two arms differ.
2. Those two identical builds timed **1.81 M vs 2.04 M obj/s — a 13%
   "difference" between the same binary**, purely from cache warming on
   the first run. Anything that compares one arm's runs against the
   other's without alternating and discarding warm-ups will find effects
   that are not there.

## What the number does not cover

- **The workload is the cheap end.** `createmany -m` objects carry little
  beyond LMA, so per-object work is small and the fixed record cost is at
  its *largest* share. Real objects with LOV, linkea and HSM xattrs do
  more work per object, so 2% is an upper bound, not a typical figure.
- **Nothing here was I/O bound.** Wall clock tracked CPU time to within
  0.5% in both modes, so even after `drop_caches` the 3 GB target read
  fast enough to keep the CPU busy. On a target where reads actually
  block, the 2% dilutes further.
- The in-kernel OSD scanner's 2.03 M obj/s figure is a different scanner
  and is not affected by this record at all.

Raw data and harness: `bench-data/2026-09-04/`.
