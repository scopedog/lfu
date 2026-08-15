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
> prototyped, faster on both backends, and freezes the Object Stream format with
> working code before any kernel work. The columns below are what each is good
> at, not a scorecard.

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
- **On ldiskfs, the userland and OSD scanners show little difference under cold
  cache. Both are limited by device bandwidth.** That convergence is
  conditional, not a property of the scanners:

  | MDT metadata bandwidth | What limits the scan |
  |---|---|
  | up to ~390 MB/s | the device — both converge (the regime measured here) |
  | ~390 MB/s – 1.7 GB/s | Option 2's CPU ceiling binds first; Option 1 tracks the device |
  | above ~1.7 GB/s | Option 1 needs threads too (`-j 4` → ~4M obj/s) |

  A production NVMe MDT clears the first threshold, so on real hardware the two
  should separate again.
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
| Metadata freshness | On-disk; lags in-memory by the journal commit interval (~5–10 s), affecting only objects modified inside that window | In-memory; current at read time |
| Begin-to-end scan skew | Scan-duration skew (minutes–hours at scale) — dominates the per-object commit lag | Same skew; "current" means current at some point within the scan window |
| Torn / mid-creation reads | Real but bounded by the commit window. At 12 M-inode scale under ~9 k creates/s: **5,979 / 4,433 / 0 skips per pass — 0.05% worst case**, all detected and counted (the earlier ~50% figure was a 1,740-inode toy namespace entirely inside the window) **[measured]** | The state never exists — inodes are only visible once fully constructed |
| Recent-file consumers | Served by the Changelog Input Scanner, not the full scan — the pipeline split that answers the recency concern for both options | Same |
| Undetectable attribute error | `metadata_csum` is **off** on Lustre MDTs (only `uninit_bg`, which covers group descriptors). An inode caught mid-update with plausible `nlink` is emitted with wrong attributes, undetectably **[measured]** | No torn reads to detect |
| Internal-object identification | LMA is insufficient — `/CONFIGS/mountdata` and `/update_log_dir/*` carry `compat=0 incompat=0`; needs a hand-maintained denylist **[measured]** | `osd_iit_iget()` already skips backend root, remote parent, project-quota inode |
| Device access | Raw block device required — weaker security posture. On ZFS the pool must additionally be **exported**: Lustre pools use `cachefile=none` + `multihost=on`, so libzpool needs a `zdb -e`-style device-scanning import **[measured]** | None |
| Enumerator parallelism | **Yes** — `-j N` over object-ID / group chunks, output identical at every thread count **[measured]** | **No** — the otable iterator is a per-device singleton. Fan-out can only offload per-object work behind it **[measured]** |
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
- LMA cannot identify every internal object; needs a denylist. **[measured]**
- Separate code path from the MDS; results need transporting for delivery.

## Option 2 — summary

**Pros**

- The only option that reads a **mounted, serving** target.
- Backend-agnostic across ldiskfs, ZFS and WBCFS.
- Attribute capture at the iterator is free on both backends, so a full
  attribute set costs nothing over bare FIDs. **[measured]**
- Reads in-memory inodes — current, and free of torn reads.
- No block-device access.
- Reuses the OI Scrub iterator, so optimisations benefit LFSCK too.
- Internal objects already filtered by `osd_iit_iget()`.
- Natural integration with the MDT RPC handler and consumer delivery ring.

**Cons**

- Novel work with no prior art.
- Slower than Option 1 whenever the scan is not device-bound — decisively so on
  warm ldiskfs, and 2.5× on ZFS once Option 1 is given threads. Its case was
  never speed. **[measured]**
- Cost lands on the MDS: CPU, memory, inode and LU-object cache.
- Iterator is a per-device singleton — no concurrent LFSCK, no concurrent
  scans. This is also why the throughput gap is structural: the parallelism that
  would close it is precluded by the current iterator design. Fan-out behind the
  singleton helps on ldiskfs (~900k with 2 workers) but breaks even on ZFS,
  where the FID lives in the LMA and the enumerator must hold each dnode
  regardless. **[measured]**
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
  consumers from a shared buffer, not one scan each. Option 2 is forced into it
  by the iterator singleton; Option 1 is forced into it by device IO
  amplification. Both then inherit the same unresolved slow-consumer policy
  (`open-questions.md` — *Slow consumers*).
- Both feed the same Object Stream pipeline; the choice is confined to the
  Input Scanner module.

## Related, but not in this comparison

The **client-side Namespace Input Scanner** — `ioctl(LL_IOC_MDC_GETINFO_V2)`
with a `statx()` fallback — is a third Input Scanner, scheduled in the same
first wave as Option 1 rather than competing with it. Most of it already exists
in tree (`architecture.md` §7a), and its `statx()` path makes it the POSIX
scanner too. Nothing here bears on it.
