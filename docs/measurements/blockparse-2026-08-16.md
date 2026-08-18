# Block Parsing: Removing iget From the Scan

**Date:** 2026-08-16
**Patch:** [`patches/itable-blockparse-v2_17_55.patch`](../../patches/itable-blockparse-v2_17_55.patch)
**Test:** [`tests/blockparse_test.sh`](../../tests/blockparse_test.sh)
**Raw data:** [`bench-data/2026-08-16/blockparse-warm.txt`](../../bench-data/2026-08-16/blockparse-warm.txt),
[`bench-data/2026-08-16/blockparse-cold.txt`](../../bench-data/2026-08-16/blockparse-cold.txt)

Two measurements pointed at the same call. Warm, eight enumerator threads spent
71% of their time spinning on one lock, and the symbol under it was
`find_inode_fast` — the inode-hash walk inside `iget_locked()`, under the
kernel-wide `inode_hash_lock`. Cold, the scan ran at queue depth ~1 on a
dependent 4 KiB read per inode-table block, and
[readahead](cold-on-fast-storage-2026-08-16.md#9-readahead-tried-measured-not-the-fix)
confirmed the diagnosis without fixing it. Both walls are `osd_iget()` →
`ldiskfs_iget()`.

`DOIF_PARALLEL` iterators do not need it. They want a FID and some attributes,
not a live `struct inode`, and both are in the inode-table block already.

## 1. What the patch does

`osd_iit_iget_raw()` maps the inode-table block with `sb_bread()` and keeps the
buffer across `next()` calls, so at a 1 KiB inode size one mapping serves four
objects. Each inode is read out of that mapping directly:

- **the FID** from `trusted.lma` in the in-inode extended attribute area — the
  space between the end of the 128-byte "good old" inode and the end of the
  inode record, where ldiskfs keeps small attributes. LMA is 24-48 bytes and is
  written at creation, so on an MDT it is essentially always there.
- **the attributes** from the raw inode fields, with the same conversions
  `ldiskfs_iget()` performs: the high halves of uid/gid, the 64-bit size, the
  `HUGE_FILE_FL` block-count units, and the two-bit post-2038 epoch extension on
  each timestamp.

Anything it cannot decode — no in-inode LMA, an `ea_inode` value, an
unsupported LMA, an inode the bitmap claims but the table does not — returns
`-EAGAIN`, and the caller repeats that object through `osd_iit_iget()`. **The
object set is therefore identical by construction**, and the fallback is where
IGIF and IDIF FID synthesis still happens.

Guarded by `lfu_blockparse` (default on). Only the private path uses it; the
scrub path still needs a real inode, because it repairs OI mappings.

### Two things that had to be got right

**An attribute is never in both places.** The first draft bailed out to the iget
path whenever `i_file_acl` was set, on the theory that an external xattr block
might hold the LMA. It cannot hold it if the in-inode area does — and that is
the normal shape of a wide-striped file on an MDT, where `trusted.lov` spills to
an external block and `trusted.lma` stays in the inode. Bailing first would have
sent exactly the interesting files down the slow path. The external block now
only matters when the in-inode lookup misses.

**Unlinked is not the same as gone.** `links_count == 0` alone is not a skip:
`ldiskfs_iget()` returns such an inode when it still has a mode and a deletion
time, which is the orphan-recovery case. The check mirrors that rule exactly,
so the two paths agree about orphans.

One difference is deliberate: `ldiskfs_iget()` verifies the inode's metadata
checksum and this does not, so a corrupt inode is reported rather than refused.
That is the right trade for a scanner whose consumer re-reads an object before
acting on it, and the wrong one for anything that trusts the attributes.

## 2. Correctness

`tests/blockparse_test.sh` lifts `osd_raw_lma()` and `osd_raw_attr()` out of the
patch, compiles them in userspace against stubbed kernel types, and checks them
on ext4 images written by `mke2fs` and `debugfs` — tools that know nothing about
our code. Four inode shapes (LMA alone; no attributes at all; LMA in the inode
with a second attribute spilled to an external block; LMA with other entries
either side of it), each at a 256- and a 1024-byte inode size, every field
against `debugfs stat`. All pass.

In the lab, the harness prints an order-independent checksum over all FIDs and a
second over every attribute of every object. Across **every row of section 3 and
section 4** — both paths, singleton and private, 1 to 16 threads, attributes on
and off:

```
objects  = 2000097
fidsum   = a589666c4d4f7123
attrsum  = fca15e310ea825d8
```

Identical. The raw parse produces bit-identical FIDs **and** bit-identical
attributes to `ldiskfs_iget()`.

## 3. Warm

2M objects, MDT mounted and serving, medians of three, OI verification off.
`bp=0` is the iget path, `bp=1` the block parse.

| enumerators | bp=0 obj/s | bp=1 obj/s | × |
|---|---|---|---|
| singleton | 746,026 | 732,636 | 0.98 |
| private, 1 | 1,065,581 | **6,873,185** | 6.45 |
| private, 2 | 1,669,530 | 12,048,777 | 7.22 |
| private, 4 | 1,607,795 | **17,392,147** | 10.82 |
| private, 8 | 1,610,384 | 14,085,190 | 8.75 |
| private, 16 | 1,610,384 | 14,185,085 | 8.81 |

**Peak to peak, 1,669,530 → 17,392,147: 10.4×.** Against the singleton the
whole change is worth 23×.

The singleton row is the control: block parsing is wired only into the private
path, and that row does not move. Whatever the other rows are measuring, it is
`DOIF_PARALLEL` plus this patch and nothing else in the build.

Attributes remain free — `bp=1` at 8 threads is 14,085,190 with them and
14,085,190 without.

### 17,392,147 is a lower bound, because `ra` was never swept warm

**Every row above ran at `lfu_ra_blocks=32`, the default, and that axis was
never varied warm** — there is not one `ra=` label in
[`blockparse-warm.txt`](../../bench-data/2026-08-16/blockparse-warm.txt) to say
otherwise. The omission was not deliberate; it followed from `lfu_par` recording
`dev`, `private`, `nthreads`, `chunk` and `recattr` in its report line but *not*
the three `osd_ldiskfs` tunables a run depends on, so `bp=` had to be a
hand-written label and `ra=` was simply never written down.

Warm, readahead can only cost. Every inode-table block is already in page
cache, so each `sb_breadahead()` is a buffer-cache lookup that finds what it
wants and accomplishes nothing — and it takes the same lock as the `sb_bread()`
it precedes, on a path where `__pv_queued_spin_lock_slowpath` is still 36.62%.
Per block that is roughly two lookups where one would do (`ooi_bp_bh` already
caches the buffer head across the four objects in a block, so this is per block,
not per object).

So the warm figures here are a floor for the block-parse path, not its ceiling,
and the 10.4× may be understated.

**Swept 2026-08-17 — it is, by 22% at one thread and 90% at four**:
[`warm-readahead-and-cold-2026-08-17.md`](warm-readahead-and-cold-2026-08-17.md).
Turning readahead off warm gives 5.21M obj/s at j1 against 4.26M at the default
`ra=32`, and 15.1M against 7.95M at j4, monotonically across the whole window
range — while the `bp=0` control moves only ~7%, because
`__ldiskfs_get_inode_loc()`'s own window is there regardless and
`inode_hash_lock` dominates that path anyway. The reasoning above was right and
the effect is larger than expected. Those rates are from a different box and 1.6×
below this document's at the same settings (the known cross-lab warm gap), so the
10.4× headline is not restated — but `ra=32` is now known to be the wrong warm
default.

None of this touches §4: cold, the window *is* the point, and at 99–100% device
utilisation the extra lock traffic hides entirely behind a 126 µs read.

### Where the time goes now

| bp=0, 8 threads | | bp=1, 8 threads | |
|---|---|---|---|
| `__pv_queued_spin_lock_slowpath` | 70.98% | `__pv_queued_spin_lock_slowpath` | 36.62% |
| `default_idle` | 6.67% | `default_idle` | 31.39% |
| `find_inode_fast` | 6.52% | `osd_raw_lma` | 10.22% |
| `memcpy_erms` | 3.08% | `__find_get_block` | 3.89% |
| `ldiskfs_xattr_ibody_get` | 1.86% | `osd_iit_iget_raw` | 2.43% |

`find_inode_fast` and `ldiskfs_xattr_ibody_get` are gone, and the top real
symbol is now our own parser. The machine is 31% **idle** at eight threads,
which is why the curve peaks at four: the work per object is now small enough
that eight enumerators cannot be kept fed on this box. The lock that remains is
in the buffer-cache lookup (`__find_get_block`) rather than the inode hash.

These profiles are indicative rather than precise — a `bp=1` pass takes 0.14 s,
so the sample is short.

## 4. Cold, and the trap in it

20M objects on a RAID0 stripe of two local NVMe SSDs, **1,397 MB/s** to one
sequential reader. Same geometry, namespace and drop-caches ritual as the
[2026-08-16 cold run](cold-on-fast-storage-2026-08-16.md), and `bp=0` reproduces
it: 245,776 obj/s at one thread against that run's 247,762.

Block parsing on its own is a **disaster** here:

| config | obj/s | bandwidth | device |
|---|---|---|---|
| bp=0, ra=0, j1 (the published curve) | 245,776 | 240 MB/s | 17% |
| bp=1, ra=0, j1 | **31,689** | 31 MB/s | 2% |
| bp=1, ra=0, j2 | 61,294 | 60 MB/s | 4% |
| bp=1, ra=0, j4 | 109,555 | 107 MB/s | 8% |
| bp=1, ra=0, j8 | 204,667 | 200 MB/s | 14% |
| bp=1, ra=0, j16 | 404,050 | 395 MB/s | 28% |

**8× slower at one thread**, and scaling at exactly 2× per doubling of threads —
the signature of a fixed number of dependent reads, one in flight per thread.
31,689 obj/s at four objects per block is 7,922 reads/s, or **126 µs per read**:
one NVMe round trip, no overlap at all.

The cause is that `ldiskfs_iget()` was never doing a bare read.
`__ldiskfs_get_inode_loc()` opens a plug and issues a **32-block readahead
window** around every inode-table block it fetches
(`EXT4_DEF_INODE_READAHEAD_BLKS = 32`), then reads the one it wants. The iget
path's 245,776 obj/s was that window's doing. Replacing `iget` with `sb_bread()`
threw it away and left the walk at queue depth 1.

So the win is not "parse instead of iget" — it is "parse instead of iget **and
bring your own readahead**". With `lfu_ra_blocks` supplying the window:

| config | obj/s | bandwidth | device |
|---|---|---|---|
| bp=1, ra=16, j1 | 227,548 | 222 MB/s | 16% |
| bp=1, ra=16, j4 | 825,427 | 806 MB/s | 58% |
| bp=1, ra=16, j16 | 1,432,672 | 1,399 MB/s | 100% |
| bp=1, ra=64, j1 | 666,026 | 651 MB/s | 47% |
| **bp=1, ra=64, j4** | **1,420,664** | 1,387 MB/s | **99%** |
| **bp=1, ra=64, j16** | **1,437,099** | 1,404 MB/s | **100%** |
| *the userspace device scanner, `-j 1`* | *1,416,559* | *1,300 MB/s* | *93%* |
| *the userspace device scanner, `-j 4`* | *1,439,300* | *1,318 MB/s* | *94%* |

**The in-kernel scanner now saturates the device.** 1,420,664 against the
userspace scanner's 1,439,300 on the same stripe in the same hour is 0.99× —
parity, within run-to-run noise.

That retires the standing conclusion from
[cold-on-fast-storage](cold-on-fast-storage-2026-08-16.md): "Option 1 takes the
device and Option 2 cannot reach it" was true of a scanner that reached each
inode through `iget`. It is not a property of running in the kernel.

The `ra=16` row is worth noting on its own: 16 blocks is *less* than ldiskfs's
own 32, and it lands at 227,548 — just under the iget path's 245,776. The window
size, not the parsing, is what sets the cold rate.

### This also re-explains the readahead U-curve

The [earlier readahead experiment](cold-on-fast-storage-2026-08-16.md#9-readahead-tried-measured-not-the-fix)
found that `lfu_ra_blocks` below 32 made things up to 3× *worse* and only helped
at 64. That was recorded as "the prefetches queue in front of the blocking read
they precede". The real explanation is now visible: on the iget path ldiskfs was
**already** prefetching 32 blocks under a plug, so any window smaller than 32
added interleaved unplugged requests to a window that was already there and
disrupted it, while 64 was the first value that actually extended it.

### The window size is the lever, and it is not done at 64

A follow-up run swept it further at one thread, with `blk_start_plug()` added
around the readahead loop (which is what `__ldiskfs_get_inode_loc()` does around
its own):

| window | obj/s | bandwidth | device |
|---|---|---|---|
| ra=32 | 381,798 | 373 MB/s | 27% |
| ra=64 | 594,180 | 580 MB/s | 41% |
| ra=128 | 895,420 · 939,722 | 875-918 MB/s | 63-66% |
| **ra=256** | **1,119,013** | 1,093 MB/s | **78%** |
| the iget path, same build (control) | 241,959 | 236 MB/s | 17% |

Threads were re-checked and had not regressed: 1,418,750 at j4, 1,435,243 at
j16.

**The plug is not what did it.** At the one point measured both ways — ra=64,
one thread — plugged was 594,180 against the unplugged run's 666,026, which is
no better and possibly slightly worse. What moves the number is how far ahead
the window reaches: 32 → 256 blocks takes one thread from 27% to 78% of the
device, monotonically. The plug is kept because it matches what ldiskfs does and
costs nothing measurable, not because it was shown to help.

So a single enumerator thread does not quite reach the userspace scanner's 93%,
and 4 threads reach 99%. Whether one thread can close the last gap by reaching
further is untested — ra=256 is a 1 MiB window and was the largest tried.

## 5. What this does not change

Warm rates at this scale are a per-object CPU measurement, not a scan estimate:
a 2M-object MDT is ~2 GB of inode table and fits entirely in page cache, and a
production MDT never will. The number that sizes a scan is the cold one.

## 6. Against the HLD's 1-hour, 4-billion-object target

| | rate | 4e9 objects |
|---|---|---|
| in-kernel, block parse + readahead, 4 threads | 1,420,664 | **0.78 h — meets it** |
| in-kernel, block parse + readahead, 1 thread | 1,119,013 | 0.99 h — meets it |
| the userspace device scanner | 1,439,300 | 0.77 h |
| in-kernel, iget path, 16 threads (previous best) | 726,457 | 1.53 h |
| in-kernel, singleton | ~202,000 | 5.5 h |

On this hardware **both options now meet the stated goal**, and the ratio
between them is 1.01.
