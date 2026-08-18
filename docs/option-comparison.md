# MDT Input Scanner — the two approaches compared

Comparison of the two approaches identified in the LFU HLD for the MDT Input
Scanner. **Both are now implemented and measured end-to-end.** Findings marked
**[measured]** come from these lab runs:

- **2026-08-05** — the Option 1 prototype against a ~1,800-inode MDT:
  correctness oracle, feature survey, internal-object leakage
  (`design-ldiskfs-scanner.md` §17).
- **2026-08-06** — both options against a 12M-inode MDT: foreground impact and
  torn-read rate at scale (`throughput-results-2026-08-06.md`). Its throughput
  figures are superseded — see the note below.
- **2026-08-07** — Option 1 verified against real ldiskfs and osd-zfs MDTs;
  Option 2's iterator measured directly, fan-out and `rec()` attributes
  (`zfs-mdt-verification-2026-08-07.md`, `ldiskfs-mdt-parallel-2026-08-07.md`,
  `scrub-decomposition-2026-08-07.md`).
- **2026-08-08** — Option 2 running end-to-end through a kernel ring on a
  mounted MDT; `DOIF_ATTR` written for osd-zfs.
- **2026-08-10** — `DOIF_ATTR` compiled and measured; the ZFS row made
  like-for-like; ldiskfs cold pass measured; thread sweep
  (`rec-attr-zfs-measured-2026-08-10.md`,
  `../bench-data/2026-08-10/sweep-and-cold-raw.txt`).

> **Superseded: the "6.7× slower" figure.** Option 2's early throughput was
> taken **via OI Scrub**, on the assumption that it drives the same iterator.
> It does not measure the iterator: `lctl lfsck_start -t scrub` times the
> *LFSCK-consumer pipeline*, because the scrub producer paces itself to LFSCK's
> window (`osd_scrub_next()` waits on `osd_scrub_has_window`). Every
> scrub-derived rate in the 08-06 run is a pipeline number. Measured directly
> with a trivial consumer, the iterator is 4–8× faster than that proxy implied.

Code references are to `../lustre-release` @ `v2_17_55-22-g61b1dc9d13`.

- **Option 1** — standalone userspace tool reading the block device directly:
  libext2fs for ldiskfs, libzpool for ZFS, on a shared core
  (`design-common-core.md`). In the tradition of `e2scan` and Lester.
- **Option 2** — in-kernel scanner driving the running osd-ldiskfs / osd-zfs
  device through `dt_it_ops`, reusing the OI Scrub iterator path, with an SPSC
  ring to a userspace consumer.

> **Read this as a comparison, not a contest.** Both are to be implemented:
> device-level userspace scanning for offline use and old servers, the OSD API
> for other backends and in-kernel scanning. Option 1 goes first — it is
> prototyped and freezes the Object Stream format with working code before any
> kernel work. The columns below are what each is good at, not a scorecard.
>
> **Note 2026-08-16:** "faster on both backends" was part of that rationale and
> is no longer true — Option 2 is level on ldiskfs and ahead on ZFS. The
> sequencing does not change, because it never rested on the rates: Option 1
> ships against unmodified servers today. The current at-a-glance table lives in
> [`option-1-vs-2.md`](option-1-vs-2.md); the throughput section below is kept
> with its dated rows and their corrections in place.

## Throughput

All figures below: 2M-object MDT, GCP `c3-standard-8`, loop-backed targets,
Lustre `v2_17_55-22` + the `rec()` attribute patches. Both columns read a full
attribute set. **Cold rows come first**: a first full scan of a large MDT reads
metadata that is not resident, so cold is what an operator gets; warm is a
per-object CPU cost, useful for comparing implementations and wrong for sizing
a scan.

| | Option 1 · device scanner | Option 2 · OSD scanner |
|---|---|---|
| **Target state** | unmounted, or a snapshot | **mounted and serving** |
| **ldiskfs · COLD** | 174k obj/s (flat at every `-j`) | **166k obj/s** (attrs free: 165.8k with, 165.8k without) |
| **ZFS · COLD** | 85.6k obj/s (−2% vs warm) | 64.8k obj/s (−41% vs warm) [^1] |
| *warm — per-object CPU cost, not for sizing a scan* | | |
| **ldiskfs · warm, 1 thread** | ~1.7M obj/s | 832k / 390k obj/s [^2] |
| **ldiskfs · warm, parallel** | ~4.2M obj/s (`-j 4`) | ~900k (2 attribute workers; enumerator stays single) |
| **ZFS · warm, 1 thread** | 87.2k obj/s | **110.5k obj/s** |
| **ZFS · warm, parallel** | **203k** (`-j 4`), plateau ~265k from `-j 8` | 107k end-to-end — fan-out gives nothing |

> **The Option 2 warm column is 2026-08-10 and is superseded twice over.** It
> predates enumerator parallelism entirely ("enumerator stays single"). Current:
> ldiskfs **17,392,147 obj/s** at 4 threads with block parsing, ZFS **561,509**
> at 16 — reversing both parallel rows above. See
> [`option-1-vs-2.md`](option-1-vs-2.md).

[^1]: Single first-pass-after-import measurement, carries Lustre mount warm-up.
      The weakest figure here; wants a repeat.
[^2]: Two labs, same object count and kernel, unexplained. Inode density,
      libcfs debug mask and MDT inode size were each tested and rejected;
      untested are the Lustre build/version, the `dm-flakey` layer, and host
      variation. The labs disagree on the *ratio* as well (2.1× vs 4.3×), so no
      stable multiplier should be quoted. Treat in-kernel **warm** rates as
      lab-specific.

### Reading it

- **Cold is bytes, warm is CPU.** Reformatting the MDT with 512-byte inodes
  halved the bytes per object and **doubled** the cold rate (174k → 351k) at an
  unchanged ~180 MB/s, while warm moved +2.6%. So
  `cold obj/s ≈ metadata read bandwidth ÷ bytes per object`, and MDT inode size
  is a real lever on scan time — with the caveat that a striped file's LOV and
  linkea may spill to an external block at 512 B. **[measured]**
  **[Qualified 2026-08-16: the formula holds for Option 1, which really is
  bandwidth-limited — it reaches 93% of a 1.4 GB/s NVMe stripe with one thread.
  It does NOT hold for Option 2, which reads the same bytes and gets 14–51% of
  that device: it is latency-bound on a dependent 4 KiB read per itable block,
  not bandwidth-bound. See `cold-on-fast-storage-2026-08-16.md`. **Superseded
  later the same day**: that latency bound was ldiskfs's, not the kernel's —
  with the inode table read directly, Option 2 is bandwidth-limited too and the
  formula holds for both. See `blockparse-2026-08-16.md`.]**
- ~~**On ldiskfs, the userland and OSD scanners show little difference under
  cold cache. Both are limited by device bandwidth.**~~ **Retracted
  2026-08-16.** Only Option 1 is device-limited. Measured on a 1,406 MB/s NVMe
  stripe with 20M objects:

  | ldiskfs, cold | Option 1 | Option 2 |
  |---|---|---|
  | 1 thread | **1,426,450 obj/s** (1,309 MB/s, 93% of the device) | 247,762 (242 MB/s, 17%) |
  | best | 1,435,080 (flat at every `-j`) | 731,452 at 16 threads (714 MB/s, 51%) |

  **Superseded 2026-08-16 (later) by
  [`blockparse-2026-08-16.md`](measurements/blockparse-2026-08-16.md).** Option 2's cold
  ceiling was `ldiskfs_iget()`, not the kernel. Reading the inode-table block
  directly and supplying an explicit readahead window in place of the one
  `__ldiskfs_get_inode_loc()` was providing:

  | ldiskfs, cold, same NVMe stripe | Option 1 | Option 2 |
  |---|---|---|
  | 1 thread | 1,416,559 (93%) | 1,119,013 (78%) |
  | best | 1,439,300 (94%) | **1,420,664 at 4 threads (99%)** |

  Cold, the two are now **1.01× apart**. Warm, Option 2 is 17,392,147 obj/s.

  The convergence measured on the loop-file labs was an artifact of a 190 MB/s
  disk that *both* scanners could saturate. The bandwidth-regime table that
  used to sit here predicted Option 1 would separate above ~390 MB/s and
  Option 2 would track the device below it; the second half is wrong at every
  bandwidth tested. Cold, the two are **5.8× apart at one thread**.
- **On ZFS neither is device-bound** — libzpool is CPU-bound in the DMU, so
  cold ≈ warm for Option 1. Faster storage buys ldiskfs almost everything and
  ZFS almost nothing; on ZFS you buy throughput with threads instead, and
  nothing moves Option 2 past its ~110k singleton wall.
- **Attribute capture is free on both backends** — the iterator already holds an
  inode or dnode, a bonus buffer and (on ZFS) an SA handle in order to read the
  FID out of the LMA, so the attributes are one bulk lookup away on a handle
  that is already open. ldiskfs 793k vs 781k bare-FID; ZFS 110.5k vs 109.3k.
  **[measured]**
- **Correctness cross-check**: the two scanners enumerated the same namespace
  through disjoint stacks — 2,001,034 visible objects on both sides on ldiskfs,
  2,000,009 on both sides on ZFS. **[measured]**

## Side by side — everything other than speed

| Aspect | Option 1 — device scanner | Option 2 — OSD API scanner |
|---|---|---|
| Backends | ldiskfs and ZFS, both **built and verified against real MDTs**, sharing one core (`lfu_target_ops`, `design-common-core.md`) **[measured]** | ldiskfs and ZFS, both running end-to-end; WBCFS still to come. Remains the **only** route to WBCFS, to live in-memory metadata and to kernel-side filtering |
| Kernel changes | None | Extends `rec()` via its unused `attr` arg, or a new index feature |
| Prior art | `e2scan`, Lester — production-proven | None; novel work, but now prototyped and running |
| Runs with MDS stopped | Yes — also unmounted MDT or snapshot | No — requires a mounted, running target |
| Works on old servers | Yes | No — needs LFU kernel support |
| Metadata freshness | On-disk; lags in-memory by the journal commit interval (~5–10 s), affecting only objects modified inside that window | In-memory, current at read time — **except on the ldiskfs `DOIF_PARALLEL` path since 2026-08-16**, which reads the buffer cache: updated at `ldiskfs_mark_inode_dirty()`, so well ahead of on-disk but behind the live `struct inode`, by an unquantified margin |
| Begin-to-end scan skew | Scan-duration skew (minutes–hours at scale) — dominates the per-object commit lag | Same skew; "current" means current at some point within the scan window |
| Torn / mid-creation reads | Real but bounded by the commit window. At 12 M-inode scale under ~9 k creates/s: **5,979 / 4,433 / 0 skips per pass — 0.05% worst case**, all detected and counted (the earlier ~50% figure was a 1,740-inode toy namespace entirely inside the window) **[measured]** | The state never exists on the scrub and ZFS paths — inodes are only visible once fully constructed. On the ldiskfs `DOIF_PARALLEL` path, narrower than Option 1's but **no longer provably nil**: the raw parse mirrors `ldiskfs_iget()`'s orphan rule exactly, but reads the buffer cache rather than the live inode. Unmeasured |
| Recent-file consumers | Served by the Changelog Input Scanner, not the full scan — the pipeline split that answers the recency concern for both options | Same |
| Undetectable attribute error | `metadata_csum` is **off** on Lustre MDTs (only `uninit_bg`, which covers group descriptors). An inode caught mid-update with plausible `nlink` is emitted with wrong attributes, undetectably **[measured]** | Nothing to detect on the scrub and ZFS paths. The raw parse deliberately skips the inode metadata checksum `ldiskfs_iget()` verifies, so a corrupt inode is *reported* rather than refused — moot while `metadata_csum` is off, and a contract question if it is ever turned on |
| Internal-object identification | LMA is insufficient — `/CONFIGS/mountdata` and `/update_log_dir/*` carry `compat=0 incompat=0`; needs a hand-maintained denylist **[measured]** | `osd_iit_iget()` already skips backend root, remote parent, project-quota inode |
| Device access | Raw block device required — weaker security posture. On ZFS the pool must additionally be **exported**: Lustre pools use `cachefile=none` + `multihost=on`, so libzpool needs a `zdb -e`-style device-scanning import **[measured]** | None |
| Enumerator parallelism | **Yes** — `-j N` over object-ID / group chunks, output identical at every thread count **[measured]** | ~~**No** — per-device singleton~~ **Yes, since 2026-08-15** — `DOIF_PARALLEL` private instances are never registered as `od_otable_it`, so N walk N inode ranges concurrently, output identical at every thread count. The singleton binds the iterator *object*, not the inode-table walk **[measured]** |
| Concurrency with LFSCK | No conflict — can scan while LFSCK runs | Blocked. `od_otable_it` is a per-device singleton (`osd-ldiskfs/osd_scrub.c:2772`, `-EALREADY`) |
| Concurrent LFU scans | Possible, but **wasteful** — N scans multiply device IO N-fold, so consumers should share one scan anyway | Impossible — the singleton forbids it. Either way **consumer fan-out is mandatory in v1**, for two independent reasons |
| Throughput | See the table above. The 705k inodes/s figure from the 08-06 run is a cold 12M-inode result on different hardware and is not comparable to the 2M-object figures **[measured]** | See the table above. The ~105k obj/s scrub figure from the 08-06 run is a pipeline number, superseded **[measured]** |
| Foreground impact while scanning | −5.1% on a ~9 k creates/s client load **[measured]** | −4.8% on the same load — equal within noise **[measured]** |
| Where the cost lands | On the scanning host, off the MDS hot path | On the MDS — CPU, memory, inode and LU-object cache pressure |
| Consumer delivery | Results must be transported to the MDS | Natural integration with the MDT RPC handler and delivery ring |
| Filter evaluation | Userspace — parser bugs are contained | Kernel — parser fuzzing becomes mandatory |
| Scan atomicity | Not atomic w.r.t. concurrent modification | Not atomic w.r.t. concurrent modification |
| Status | **First wave.** Both backends verified against real MDTs, zero oracle misses; Object Stream encoding is the next work **[measured]** | **Second wave.** Running end-to-end on both backends via the kernel ring; needs LMA flags on the wire, a multi-target interface, foreground-impact data and the upstream `rec()` conversation **[measured]** |

## Option 1 — summary

**Pros**

- No kernel changes; nothing to land upstream to start.
- Strong prior art (`e2scan`, Lester), reducing development effort.
- Runs with the MDS stopped, and on an unmounted MDT or snapshot.
- Sequential device-bandwidth reads; bypasses OSD and filesystem locking.
- Works on servers with no LFU support.
- No LFSCK conflict, and no singleton — concurrent scans are possible (though
  fan-out is still the right answer, to avoid multiplying device IO).
- Prototype exists and passes a correctness oracle — zero misses. **[measured]**

**Cons**

- Cannot read a mounted, serving target — and on ZFS the pool must be
  **exported**, not merely unmounted (Lustre pools use `cachefile=none` +
  `multihost=on`). **[measured]**
- Requires raw block-device access.
- On-disk state lags in-memory state by the journal commit interval (~5–10 s);
  a tiny fraction of a realistic namespace, but must be validated and
  skip-counted. **[measured]**
- No inode checksums, so mid-update inodes with plausible `nlink` are emitted
  with wrong attributes, undetectably. **[measured]**
- LMA cannot identify every internal object; needs a denylist. **[measured; filed upstream as LU-20602]**
- Separate code path from the MDS; results need transporting for delivery.

## Option 2 — summary

**Pros**

- The only option that reads a **mounted, serving** target.
- Backend-agnostic across ldiskfs, ZFS and WBCFS.
- Attribute capture at the iterator is free on both backends, so a full
  attribute set costs nothing over bare FIDs. **[measured]**
- Reads in-memory inodes — current, and free of torn reads. *Qualified since
  2026-08-16: true of the scrub path and both ZFS paths; the ldiskfs
  `DOIF_PARALLEL` path reads the buffer cache instead.*
- **Enumerator parallelism and LFSCK coexistence, both measured** — N private
  iterators per device, concurrent with a verifying scrub.
- **At or above Option 1's rate on both backends** — cold parity on ldiskfs
  (1.01×), 1.9× cold and 2.5× warm on ZFS.
- No block-device access.
- Reuses the OI Scrub iterator, so optimisations benefit LFSCK too.
- Internal objects already filtered by `osd_iit_iget()`.
- Natural integration with the MDT RPC handler and consumer delivery ring.

**Cons**

- Novel work with no prior art.
- ~~Slower than Option 1 whenever the scan is not device-bound.~~ **Retired
  2026-08-15/16.** It is now level with Option 1 on ldiskfs (1.01× cold) and
  ahead on ZFS (1.9× cold, 2.5× warm). Its case was never speed, and it no
  longer needs to be. **[measured]**
- Cost lands on the MDS: CPU, memory, buffer and LU-object cache. **This is the
  top open item** — no foreground-impact measurement exists for the parallel
  path on either backend.
- ~~Iterator is a per-device singleton — no concurrent LFSCK, no concurrent
  scans.~~ **Retired 2026-08-15**: `DOIF_PARALLEL` private instances run N per
  device and concurrently with a verifying scrub, with the singleton path
  failing `-114` on the same build as the control. Fan-out behind the iterator
  is still wanted for one-scan-N-consumers, but is no longer the parallelism
  story. **[measured]**
- Two correctness items the block parse introduced: it reads the buffer cache
  rather than the live inode, and it does not verify the inode metadata
  checksum. Both unquantified.
- In-kernel warm rates have not reproduced across labs (832k vs 390k on
  ldiskfs); three candidate causes tested and rejected. Unresolved.
- Upstream acceptance of the `rec()` extension is still an open question.
- Kernel-side filter evaluation makes parser fuzzing mandatory.
- Still a fuzzy snapshot — not atomic w.r.t. concurrent modification.

## Common to both

- Neither scan is atomic with respect to concurrent modification — and
  begin-to-end scan skew (the scan's own duration) dominates either option's
  per-object staleness. The Changelog Input Scanner is the designed answer for
  consumers that need recent or exact results, independent of which scanner is
  chosen.
- Both need explicit skip and gap accounting, so that an incomplete listing is
  never presented as a complete one.
- **Consumer fan-out is mandatory in v1 for both** — one scan feeding many
  consumers from a shared buffer, not one scan each. Option 1 is forced into it
  by device IO amplification; Option 2 was forced into it by the iterator
  singleton, and now wants it for Option 1's reason instead — at 99% of the
  device, a second concurrent scan costs a second scan's worth of reads. Both then inherit the same unresolved slow-consumer policy
  (`open-questions.md` — *Slow consumers*).
- Both feed the same Object Stream pipeline; the choice is confined to the
  Input Scanner module.

## Related, but not in this comparison

The **client-side Namespace Input Scanner** — `ioctl(LL_IOC_MDC_GETINFO_V2)`
with a `statx()` fallback — is a third Input Scanner, scheduled in the same
first wave as Option 1 rather than competing with it. Most of it already exists
in tree (`architecture.md` §7a), and its `statx()` path makes it the POSIX
scanner too. Nothing here bears on it.
