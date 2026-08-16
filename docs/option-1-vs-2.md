# MDT Input Scanner — Option 1 vs Option 2 at a glance

One-table summary. Full discussion, caveats and provenance in
[`option-comparison.md`](option-comparison.md); raw measurements in
[`../bench-data/`](../bench-data/).

**Rewritten 2026-08-16.** Every throughput row below changed twice in two days:
[`parallel-osd-measured-2026-08-15.md`](parallel-osd-measured-2026-08-15.md)
(`DOIF_PARALLEL` private iterators) and
[`blockparse-2026-08-16.md`](blockparse-2026-08-16.md) (reading the inode table
instead of one `iget` per inode). The version of this table dated 2026-08-10 is
superseded in full; its numbers are preserved in §"What the old table said" at
the end, because two of its conclusions were wrong in instructive ways.

**Cold is what a first full scan gets; warm is a per-object CPU cost — useful
for comparing implementations, wrong for sizing a scan.** Cold rows are 20M
objects on a 1,397 MB/s NVMe stripe (ldiskfs) and a same-lab pool (ZFS); warm
rows are 2M objects, page-cache resident, on GCP `c3-standard-8`.

| | **Option 1 — device scanner** | **Option 2 — OSD scanner** |
|---|---|---|
| **What it is** | Userspace tool reading the target directly: libext2fs (ldiskfs), libzpool (ZFS), on a shared core | In-kernel scanner over the OI Scrub otable iterator (`dt_it_ops`), with an SPSC ring to userspace |
| **Target state** | Unmounted, or a snapshot. On ZFS the pool must be **exported** | **Mounted and serving** |
| **Works on unmodified servers** | Yes | No — needs the OSD patches |
| **Kernel changes** | None | `DOIF_ATTR` on `rec()`, `DOIF_PARALLEL` on `init()`, raw inode-table parsing on the private path |
| ***— Throughput, cold —*** | | |
| **ldiskfs · cold** | 1,439,300 obj/s (`-j 4`, 94% of the stripe) | **1,420,664 obj/s** (4 threads, 99% of the stripe) — **0.99×, parity** |
| **ZFS · cold** | 220,023 obj/s (`-j 16`, best; identical warm or cold — libzpool's ARC dies with the process) | **424,469 obj/s** (private j8) — **1.93×** |
| ***— Throughput, warm —*** | | |
| **ldiskfs · warm, 1 thread** | ~1.7M obj/s | **6,873,185 obj/s** (private, block parse) |
| **ldiskfs · warm, parallel** | ~4.2M obj/s (`-j 4`) | **17,392,147 obj/s** (private j4, block parse) |
| **ZFS · warm, 1 thread** | 81,633 obj/s | 193,713 obj/s |
| **ZFS · warm, parallel** | 220,023 obj/s (`-j 16`, best) | **561,509 obj/s** (private j16) — **2.52×** at j8 |
| ***— Behaviour —*** | | |
| **Enumerator parallelism** | **Yes** — `-j N`, output identical at every thread count | **Yes** — `DOIF_PARALLEL`, N private instances per device, output identical at every thread count |
| **Attribute capture** | Always reads a full attribute set | **Free** — identical rates with `DOIF_ATTR` on and off, on both backends and both parse paths |
| **What bounds it** | ldiskfs: the device. ZFS: libzpool lock contention (CPU) | ldiskfs: the device cold, and CPU warm — the box goes 31% idle at 8 threads. ZFS: the DMU, inherently |
| **Metadata freshness** | On-disk; lags in-memory by the journal commit interval (~5–10 s) | ZFS and the scrub path: in-memory, current at read time. **ldiskfs `DOIF_PARALLEL`: the buffer cache** — updated at `ldiskfs_mark_inode_dirty()`, so fresher than on-disk but not the live `struct inode` (unquantified — see below) |
| **Torn / mid-creation reads** | Real but bounded — 0.05% worst case at 12M inodes under load, all detected and counted | Narrower than Option 1's, but **no longer provably nil** on the ldiskfs private path |
| **Inode checksum** | Verified where available; `metadata_csum` is off on Lustre MDTs, so detection is heuristic | Scrub path verifies; the raw parse does not — a corrupt inode is *reported*, not refused |
| **Concurrency with LFSCK** | No conflict | **No conflict** — measured, with the singleton path failing `-114` on the same build as the control |
| **Where the cost lands** | On the scanning host, off the MDS hot path | On the MDS — CPU, memory, buffer cache |
| **Filter evaluation** | Userspace — parser bugs contained | Kernel — parser fuzzing becomes mandatory |
| **Route to WBCFS** | No | **Yes — the only one** |
| **Status** | **First wave.** Both backends verified on real MDTs, zero oracle misses; Object Stream encoding next | **Second wave.** Both backends end-to-end, parallel, LFSCK-concurrent, at or above Option 1's rate; needs foreground-impact data, LMA flags on the wire, multi-target interface, upstream review |

**Four things the table does not say on its own:**

1. **Cold is bytes, warm is CPU** — still true, and now the *only* thing that
   sizes a scan. Halving MDT inode size to 512 B doubled the cold rate at
   unchanged bandwidth while warm moved +2.6%. A 17.4M obj/s warm figure is a
   per-object CPU measurement on a namespace that fits in page cache; a
   production MDT's never will.
2. **Cold parity is not a coincidence, it is the same work.** Both options now
   read the inode table sequentially and parse it. Option 2 was slower for as
   long as it reached each inode through `ldiskfs_iget()`; the moment it stopped,
   the two converged to within run-to-run noise (1.01). Neither can beat the
   other by much, because both are reading the same bytes off the same device.
3. **Option 2's readahead is load-bearing.** Removing `iget` also removed
   ldiskfs's own 32-block window inside `__ldiskfs_get_inode_loc()`, and block
   parsing *without* an explicit window measures 31,689 obj/s — 8× worse than the
   iget path. The cold row above depends on a module parameter that should be
   derived from the device.
4. **Option 2's case is no longer "not speed".** It is now the faster path on
   ZFS (1.9× cold, 2.5× warm) and level on ldiskfs, *and* it keeps the reasons it
   was chosen: the only one that reads a mounted, serving target, the only route
   to WBCFS, the only place in-kernel filter pushdown can happen. Option 1 keeps
   its own: unmodified servers, unmounted targets, snapshots, and the cost
   landing off the MDS. **Both ship.**

---

## What the old table said

The 2026-08-10 version of this page concluded:

> **On ldiskfs the two show little difference under cold cache, because both are
> limited by device bandwidth** — which holds only while the device is the
> constraint (up to ~390 MB/s here). On faster MDT storage Option 2 reaches its
> CPU ceiling first and the two diverge again.

> **Option 1 is the faster path on both backends, and Option 2's case was never
> speed.**

Both were wrong, and neither for the reason the caveats anticipated:

- The "little difference under cold cache" tie (174k vs 166k obj/s) was an
  artifact of a **190 MB/s disk**, retracted in
  [`cold-on-fast-storage-2026-08-16.md`](cold-on-fast-storage-2026-08-16.md). On
  NVMe the options *did* diverge — but the prediction that Option 2 would hit a
  *CPU* ceiling was also wrong. It was latency-bound at queue depth ~1, one
  dependent read per inode-table block.
- "Option 1 is the faster path on both backends" survived four days. On ZFS it
  reversed on 2026-08-15 (parallel enumeration); on ldiskfs it went to parity on
  2026-08-16 (block parsing).
- The old warm rows carried a footnote about two labs disagreeing 832k vs 390k
  on the same object count and kernel, with no explanation found. That gap is
  **still unexplained** and is the reason warm rates are quoted per-lab and never
  as a cross-lab multiplier.

The pattern in all three: a ceiling was attributed to an architecture when it
belonged to one call, and a measurement was generalised past the hardware it was
taken on.
