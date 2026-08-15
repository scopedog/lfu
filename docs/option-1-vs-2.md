# MDT Input Scanner — Option 1 vs Option 2 at a glance

One-table summary. Full discussion, caveats and provenance in
[`option-comparison.md`](option-comparison.md); raw measurements in
[`../bench-data/2026-08-10/`](../bench-data/2026-08-10/).

Throughput figures: 2M-object MDT, GCP `c3-standard-8`, loop-backed targets,
Lustre `v2_17_55-22` + the `rec()` attribute patches, both columns reading a
full attribute set. **Cold is what a first full scan gets; warm is a per-object
CPU cost — useful for comparing implementations, wrong for sizing a scan.**

| | **Option 1 — device scanner** | **Option 2 — OSD scanner** |
|---|---|---|
| **What it is** | Userspace tool reading the target directly: libext2fs (ldiskfs), libzpool (ZFS), on a shared core | In-kernel scanner over the OI Scrub otable iterator (`dt_it_ops`), with an SPSC ring to userspace |
| **Target state** | Unmounted, or a snapshot. On ZFS the pool must be **exported** | **Mounted and serving** |
| **Works on unmodified servers** | Yes | No — needs the OSD patches |
| **Kernel changes** | None | Extends `rec()` via its unused `attr` argument |
| ***— Throughput, cold —*** | | |
| **ldiskfs · cold** | 174k obj/s, flat at every `-j` | **166k obj/s** |
| **ZFS · cold** | 85.6k obj/s (−2% vs warm) | 64.8k obj/s (−41% vs warm) [^1] |
| ***— Throughput, warm —*** | | |
| **ldiskfs · warm, 1 thread** | ~1.7M obj/s | 832k / 390k obj/s [^2] |
| **ldiskfs · warm, parallel** | ~4.2M obj/s (`-j 4`) | ~900k (2 attribute workers) |
| **ZFS · warm, 1 thread** | 87.2k obj/s | **110.5k obj/s** |
| **ZFS · warm, parallel** | **203k** (`-j 4`); plateau ~265k from `-j 8` | 107k end-to-end — fan-out gives nothing |
| ***— Behaviour —*** | | |
| **Enumerator parallelism** | **Yes** — `-j N`, output identical at every thread count | **No** — per-device singleton; fan-out only offloads per-object work |
| **Attribute capture** | Always reads a full attribute set | **Free** — ldiskfs 793k vs 781k bare, ZFS 110.5k vs 109.3k bare |
| **What bounds it** | ldiskfs: the device. ZFS: libzpool lock contention (CPU) | ldiskfs: CPU above ~390 MB/s of device. ZFS: the DMU, inherently |
| **Metadata freshness** | On-disk; lags in-memory by the journal commit interval (~5–10 s) | In-memory; current at read time |
| **Torn / mid-creation reads** | Real but bounded — 0.05% worst case at 12M inodes under load, all detected and counted | The state never exists |
| **Concurrency with LFSCK** | No conflict | Blocked — the iterator singleton returns `-EALREADY` |
| **Where the cost lands** | On the scanning host, off the MDS hot path | On the MDS — CPU, memory, inode and LU-object cache |
| **Filter evaluation** | Userspace — parser bugs contained | Kernel — parser fuzzing becomes mandatory |
| **Route to WBCFS** | No | **Yes — the only one** |
| **Status** | **First wave.** Both backends verified on real MDTs, zero oracle misses; Object Stream encoding next | **Second wave.** Running end-to-end on both backends; needs LMA flags on the wire, multi-target interface, foreground-impact data, upstream `rec()` review |

[^1]: Single first-pass-after-import measurement, carries Lustre mount warm-up —
      the weakest figure here; wants a repeat.
[^2]: Two labs, same object count and kernel, unexplained. Inode density, libcfs
      debug mask and MDT inode size were each tested and rejected; untested are
      the Lustre build/version, the `dm-flakey` layer and host variation. The
      labs disagree on the ratio too (2.1× vs 4.3×), so no stable multiplier
      should be quoted — treat in-kernel **warm** rates as lab-specific.

**Three things the table does not say on its own:**

1. **Cold is bytes, warm is CPU.** Halving MDT inode size to 512 B doubled the
   cold rate (174k → 351k) at an unchanged ~180 MB/s, while warm moved +2.6%.
   So `cold obj/s ≈ metadata read bandwidth ÷ bytes per object`.
2. **On ldiskfs the two show little difference under cold cache, because both
   are limited by device bandwidth** — which holds only while the device is the
   constraint (up to ~390 MB/s here). On faster MDT storage Option 2 reaches its
   CPU ceiling first and the two diverge again.
3. **Option 1 is the faster path on both backends, and Option 2's case was never
   speed.** Option 2 is the only one that reads a mounted, serving target, the
   only route to WBCFS, and the only place in-kernel filter pushdown can happen.
   The sequencing follows from that, not from the rates.
