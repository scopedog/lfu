# Cold Scanning on Fast Storage — a Standing Conclusion Retracted

**Date:** 2026-08-16
**Raw data:** [`bench-data/2026-08-16/local-ssd-cold.txt`](../../bench-data/2026-08-16/local-ssd-cold.txt)
**Retracts:** the "cold is device-bound, flat at every thread count, and a tie
between the two options" result recorded in `option-comparison.md` and repeated
in `parallel-osd-measured-2026-08-15.md` §4 and §6b.

Every cold figure this project had ever produced came from a loop file on a
cloud boot disk delivering **~190 MB/s**. The scanners both hit ~186k obj/s
there, which at 1 KiB inodes is ~190 MB/s, and we concluded that cold is
storage-bound and therefore identical for both. That conclusion was about the
disk. Given a device that can do **1,406 MB/s** it does not survive.

Lab: GCP `c3-standard-8-lssd`, same 8-vCPU Xeon and same kernel as every prior
lab, MDT on a RAID0 stripe of two local NVMe SSDs, **20,000,101 objects** (10×
the usual, so a cold pass still lasts >10 s at GB/s). ldiskfs only — the ZFS
cold question was already answered (CPU-bound, scales with threads).

## 1. What the device can do

| | MB/s |
|---|---|
| one local SSD, O_DIRECT sequential | 738 |
| the stripe, 1 reader | 1,399 |
| the stripe, 2 / 4 / 8 readers | 1,406 |

One sequential reader saturates it. 1,406 MB/s is the ceiling everything below
is measured against.

## 2. Option 2 cold: latency-bound, and it scales

| config | rate | bandwidth | device used |
|---|---|---|---|
| singleton | 202,376 | 198 MB/s | 14% |
| private, 1 thread | 247,762 | 242 MB/s | 17% |
| private, 2 | 421,569 | 412 MB/s | 29% |
| private, 4 | 621,179 | 607 MB/s | 43% |
| private, 8 | 718,549 | 702 MB/s | 50% |
| **private, 16** | **731,452** | 714 MB/s | 51% |

Repeats: singleton 203,966 (+0.8%), j4 621,275 (+0.02%).

**Cold scales 3.6× with threads.** Every run reads the same 19.5 GB — 1 KiB
per object, exactly as the bytes-per-object model predicts — so what threads
change is not how much is read but how fast it arrives. And even at 16 threads
the scanner draws only half the device.

This is the direct retraction of "threads buy nothing cold". They buy 3.6×.
The earlier labs could not show it because at 190 MB/s the disk was already the
constraint at one thread.

## 3. Option 1 cold: device-bound, with one thread

| config | rate | bandwidth |
|---|---|---|
| `-j 1` | 1,426,450 | 1,309 MB/s |
| `-j 2` | 1,432,158 | 1,311 MB/s |
| `-j 4` | 1,435,080 | 1,314 MB/s |
| `-j 8` | 1,434,569 | 1,313 MB/s |
| warm `-j 1` / `-j 4` / `-j 8` | 1,426,347 / 1,435,029 / 1,434,886 | — |

Flat at every `-j`, warm identical to cold, pinned at **93% of the raw stripe**.
Option 1 is genuinely device-bound — and gets there with a single thread.

## 4. The comparison, corrected

| cold | Option 1 | Option 2 | ratio |
|---|---|---|---|
| 1 thread | **1,426,450** | 247,762 | **5.76× Option 1** |
| each side's best | 1,435,080 | 731,452 | **1.96× Option 1** |
| device utilisation | 93% | 17% → 51% | — |

**Cold was never a tie.** On slow storage both scanners saturated the disk and
looked identical; on fast storage Option 1 takes the device and Option 2 cannot
reach it.

### Why

The userspace scanner reads the inode table in large sequential runs —
`ext2fs_inode_scan` walks a whole block group's itable. The in-kernel path
reaches each inode through `osd_iget` → `ldiskfs_iget` →
`__ldiskfs_get_inode_loc` → `sb_bread`: one 4 KiB buffer-cache read per
itable block, issued dependently. At queue depth ~1 that is **latency-bound**,
which explains both halves of the result — threads help (more requests in
flight) and still cannot catch a device that one sequential reader saturates.

## 5. Warm stops existing at scale

| | cold | warm |
|---|---|---|
| singleton | 202,376 | 223,322 |
| private j1 | 247,762 | 298,477 |
| private j2 | 421,569 | 480,425 |
| private j4 | 621,179 | 540,967 |
| private j8 | 718,549 | 465,953 |

At 20M objects the working set — 19.5 GB of inode table plus the kernel inode
cache — does not fit in 31 GiB of RAM, so warm is barely distinguishable from
cold and is *worse* than cold at high thread counts (cache thrash).

**The 1.9M obj/s warm figures from the 2M-object labs are a small-namespace
artifact.** A 2M-object MDT is ~2 GB of itable, which fits in page cache
entirely; a production MDT never will. Warm remains the right way to compare
two implementations' per-object CPU cost, and the wrong way to size a scan —
that was already in the record, but this makes it concrete.

## 6. Against the HLD's 1-hour, 4-billion-object target

| | rate | 4e9 objects |
|---|---|---|
| Option 1 | 1,435,080 | **0.78 h — meets it** |
| Option 2, sharded | 731,452 | 1.52 h |
| Option 2, singleton | 202,376 | 5.49 h |

Sharding takes the in-kernel scanner from 5.5 h to 1.5 h on this hardware,
which is a real gain and the largest single improvement this project has
produced. It is still not the target, and on this evidence **Option 1 is the
only one of the two that meets the HLD's stated goal**.

## 7. What this changes in the record

| Claim | Status |
|---|---|
| "cold obj/s ≈ metadata read bandwidth ÷ bytes per object" | **holds for Option 1 only.** Option 2 reads the same bytes and gets a third of the bandwidth |
| "cold is flat at every thread count" | **true for Option 1, false for Option 2** (3.6×) |
| "ldiskfs cold is a 1% tie between the options" | **retracted** — an artifact of 190 MB/s storage |
| the bandwidth-regime table in the design record | **wrong**: it assumed Option 2 tracks the device cold. It does not, at any bandwidth measured here |
| "Option 1 takes the device and Option 2 cannot reach it" (§4) | **superseded 2026-08-16** by [block parsing](blockparse-2026-08-16.md): with `iget` removed and an explicit readahead window, Option 2 reaches 99% of the same device. The gap was `ldiskfs_iget()`, not the kernel |
| "parallel enumeration is a warm-path lever only" | **retracted** — it is worth 3.6× cold |
| ZFS cold scales with threads | unchanged, and now the same mechanism is understood on both backends |

The honest summary of the whole parallel-enumeration exercise is now: it helps
cold as well as warm, by more than we thought; and it does not close the gap to
the device scanner on ldiskfs, which is wider cold than we believed.

## 8. What to measure next

The in-kernel path is latency-bound on a dependent 4 KiB read per itable
block. Two things would test whether that is fixable without leaving the
kernel:

1. **Readahead on the itable.** `osd_iit_iget()` knows it is walking inodes in
   ascending order within a group; a `sb_breadahead()` for the next N blocks
   costs nothing and should raise queue depth without more threads.
2. **Batch the inode reads.** Read a whole itable block and parse its 4 inodes
   before calling `osd_iget` at all — closer to what the userspace scanner
   does, and the same change that would relieve `inode_hash_lock` warm.

Both are larger than `DOIF_PARALLEL` and neither is needed to ship it, but
they are where the remaining 2× lives.

## 9. Readahead: tried, measured, not the fix

`patches/itable-readahead-v2_17_55.patch` adds `sb_breadahead()` on the next N
itable blocks, N as a module parm. Raw data:
[`bench-data/2026-08-16/itable-readahead.txt`](../../bench-data/2026-08-16/itable-readahead.txt).

Cold, one thread, against the 248,266 baseline: **ra=4 85,132 · ra=8 126,905 ·
ra=16 202,750 · ra=32 295,479 · ra=64 339,704 · ra=128 305,933.** A clean U with
its optimum at 64 (**+37%**). Below ~32 it is a 3× *pessimisation*.

> **Corrected 2026-08-16 (later).** This was first explained as "the critical
> read queues behind its own prefetches". The real cause, found while measuring
> [block parsing](blockparse-2026-08-16.md#4-cold-and-the-trap-in-it), is that
> `__ldiskfs_get_inode_loc()` **already** issues a plugged 32-block readahead
> window around every inode-table block it fetches
> (`EXT4_DEF_INODE_READAHEAD_BLKS = 32`). Every number in this section was
> therefore measured on top of a 32-block window that was already there: values
> below 32 only added unplugged interleaved requests to it, and 64 was the first
> value that extended it. The whole of §2's 202,376-731,452 range is that
> built-in window's doing, not a bare read.

It does not compose with threads — 1.2× at j1, 1.15× at j2, 1.02× at j4,
**0.95× at j8** — because readahead and threads buy the same thing, queue
depth. Best in-kernel cold is still 682,132 against Option 1's 1,438,615 at
94% of the device: **0.47×, unchanged.**

So §8's first suggestion confirms the diagnosis and cannot fix it *on its own*.
**The second suggestion is the one that matters**: parse whole itable blocks
instead of one `iget` per inode.

> **Followed up 2026-08-16 (later).** Done, and measured, in
> [blockparse-2026-08-16.md](blockparse-2026-08-16.md). Block parsing is worth
> **10.4×** warm. Cold it is worth nothing by itself — it is 8× *slower*,
> because dropping `iget` also drops ldiskfs's built-in readahead window — but
> parsing **plus** an explicit window of 64+ blocks reaches **1,420,664 obj/s at
> 99% of the device**, against the userspace scanner's 1,439,300 on the same
> stripe. The two together are what §4's comparison was missing.
