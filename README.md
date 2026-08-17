# LFU — Lustre Find Utility

Server-side namespace scanning and reporting subsystem, targeted for **Lustre
2.19+ (TLC)**. Replaces and unifies the ad-hoc scanners in use today — "Lester
the Lustre Lister", OSD OI Scrub, Changelog crawl, client-side `lfs find` — with
a structured, parallel, modular Object Stream pipeline running directly on MDTs
and OSTs. Minimal data transfer, no intermediate database, open API for
third-party integration.

- **Jira epic (WC):** [LU-20462](https://jira.whamcloud.com/browse/LU-20462) — Open, assignee Artem Blagodarenko, created 2026-07-08
- **Tracking ticket (TLC):** TLU-186 — In Progress
- **High-level design:** [`docs/reference/lfu-hld.pdf`](docs/reference/lfu-hld.pdf) — Dilger, v0.1, 2026-04-03 — **source of truth**
- **Requirements:** [`docs/reference/lfu-requirements.pdf`](docs/reference/lfu-requirements.pdf) (Confluence [78741505](https://thelustrecollective.atlassian.net/wiki/spaces/Lustre/pages/78741505) export, 2026-08-05)
- **Public summary:** [`docs/reference/lug2026-lustre-218-and-beyond-dilger.pdf`](docs/reference/lug2026-lustre-218-and-beyond-dilger.pdf) — LUG 2026, slides 20–22 are LFU
- **Not yet obtained:** LU-17814 (source of the client namespace scanner), LU-16742 / LU-17820 (LMR), LU-16524
- **Upstream reference tree:** `../lustre-release` at `v2_17_55-2-gd717692511`

## Benchmark results

GCP c3-standard-8 labs, Rocky 9.8, kernel 5.14.0-687.36.1, Lustre v2_17_55 built
from source. Absolute rates are not server-class claims — the ratios and the
mechanisms transfer, the numbers do not.

**Cold rows first** — a first full scan of a large MDT reads metadata that is not
resident, so cold is what an operator gets. Warm is a per-object CPU cost: the
right way to compare two implementations, the wrong way to size a scan.

| | Option 1 · device scanner | Option 2 · OSD scanner | faster by |
|---|---|---|---|
| **Target state** | unmounted, or a snapshot | **mounted and serving** | — |
| **ldiskfs · COLD**<br>*NVMe, ~1,400 MB/s stripe, 20M objects* | **1,439,300**<br>*1,318 MB/s = 94% of the device, flat at every `-j`* | 1,119,013 (1 thread)<br>**1,420,664 at 4 — 99% of the device** | 1.01× Option 1 |
| **ZFS · COLD** | 83,752 (`-j 1`)<br>225,480 (`-j 16`) | **97,304** (singleton)<br>**410,529** (8 threads) | **1.82× Option 2** |
| **ldiskfs · warm** | 1,818,270 (1 thread)<br>4,545,675 (`-j 4`) | **6,873,185** (1 thread)<br>**17,392,147** (4 threads) | **3.8× Option 2** |
| **ZFS · warm** | 84,282 (1 thread)<br>230,151 (`-j 16`) | **186,038** (1 thread)<br>**531,940** (16 threads) | **2.21× / 2.31× Option 2** |

**Provenance.** The ZFS rows and the ldiskfs warm rows come from **one box that
built both OSDs and ran both scanners in one session**
(`bench-data/2026-08-15/same-lab-head-to-head.txt`). The ldiskfs cold rows come
from boxes whose MDT was a RAID0 stripe of two local NVMe SSDs, each running both
scanners against one 20M-object namespace. Every machine was the same instance
type and kernel, and the namespaces reproduced identical FID checksums across
every lab.

Objects per CPU-second, warm, **derived** as rate ÷ threads — no run has captured
user/sys time, so this assumes saturation and is invalid cold. These are the
`iget`-path rates; block parsing raises the ldiskfs Option 2 row by roughly an
order of magnitude and has not been re-derived here:

| Warm · obj per CPU-second | 1 thread | 2 | 4 | 8 |
|---|---:|---:|---:|---:|
| **ldiskfs** · Option 1 | **1,818,270** | 1,538,536 | 1,136,419 | 510,229 |
| **ldiskfs** · Option 2 | 1,249,281 | 1,033,110 | 496,549 | 250,263 |
| **ZFS** · Option 1 | 84,282 | — | 42,052 | 27,322 |
| **ZFS** · Option 2 | **175,848** | 140,694 | 98,760 | 61,083 |

On the `iget` path, ldiskfs Option 2 at two threads returned 2,066,219 obj/s for
1,033,110 per core; at eight it returned the same throughput for 250,263 — four
times the CPU for nothing. **Block parsing moves that wall rather than removing
it:** the peak is now at four threads and eight is slower, because the per-object
work is small enough that an 8-vCPU box sits 31% idle. The setting to pick is
still the peak, and it is still low.

Every rate above is accompanied by an order-independent checksum over all FIDs,
and for the block-parse runs a second over every attribute of every object:
`fidsum a589666c4d4f7123` (ldiskfs, 2,000,097 objects), `attrsum
fca15e310ea825d8`, `39d945cad6c1b98d` (ZFS) — identical across both backends, 1
to 16 threads, attributes on and off, both parse paths, and the singleton
baselines, reproduced across four separate labs.

## The design in one paragraph

Everything is a module operating on an **Object Stream** (FID-identified objects
with optional attributes). Three module types stack: **Input Scanner** (MDT, OST,
Changelog, index, raw file) → **Filter Rule** (match, merge, aggregate) →
**Output Format** (text, pathnames, JSON, direct consumer ingest). The initial
Input Scanners are *userspace*: a libext2fs block-device reader on the server (in
the tradition of `e2scan` and Lester) and a namespace traversal on the client
extracted from LU-17814. Kernel work — the OSD API scanner, `circ_buf` export,
bulk RPC — comes later. Target: **1M objects/sec/MDT**, ~1h for a full 4-billion-
object MDT scan, excluding pathname generation.

## Requirements, by stated priority

| Priority | Gap | Wanted |
|---|---|---|
| **Highest** | No efficient server-side namespace scanner | Read inodes at the OSD layer; send only matching/requested attributes |
| **Highest** | No unified scan pipeline | One modular pipeline, pluggable backends, common stream format, merge operator |
| **High** | No structured binary Object Stream | FlatBuffers or MsgPack — schema evolution, language-neutral |
| **High** | No MDT-side indexes for common queries | atime / file size / mirror status indexes → `O(result-set)`, not `O(namespace)` |
| **High** | No parallel multi-MDT scan with merge | Per-MDT scanners + Merge operator that combines and optionally sorts |
| **Medium** | No zero-copy kernel→userspace export | Lockless ring buffer, no copies on the hot path |
| **Medium** | No access control on scan RPCs | Server enforces user/project permissions before returning entries |
| **Medium** | Consumers re-implement scanning | One API for FLR/EC resync, PCC-RO, HSM, tiered storage — one scan, N consumers |
| **Low** | Third-party tools scan inefficiently | Documented open scanner API (RobinHood, PoliMor, GUFI) |

Rollout is incremental with **no flag day**: server-only mode (already improves
`lfs find`) → PtlRPC transport → full user access.

## Documents

| Doc | Contents |
|-----|----------|
| [`docs/architecture.md`](docs/architecture.md) | The HLD design, plus analysis and a suggested build order |
| [`docs/design-ldiskfs-scanner.md`](docs/design-ldiskfs-scanner.md) | **ldiskfs device scanner — first wave.** Design + prototype results |
| [`docs/design-zfs-scanner.md`](docs/design-zfs-scanner.md) | **ZFS device scanner.** Design + prototype (libzpool, snapshot-first) |
| [`docs/design-osd-scanner.md`](docs/design-osd-scanner.md) | **OSD API scanner — second wave.** In-kernel, all backends; gated on the throughput gap |
| [`docs/parallel-osd-scanner-2026-08-15.md`](docs/parallel-osd-scanner-2026-08-15.md) | **Parallel enumeration (step 5) — design.** `DOIF_PARALLEL` private iterators + the `lfu_par` harness |
| [`docs/parallel-osd-measured-2026-08-15.md`](docs/parallel-osd-measured-2026-08-15.md) | **Parallel enumeration — measured, both backends.** ldiskfs 2.03M obj/s (2.4×, wall = `inode_hash_lock`); ZFS 561k (3.64×) and now **2.5× the userspace scanner**; LFSCK coexistence proven |
| [`docs/blockparse-2026-08-16.md`](docs/blockparse-2026-08-16.md) | **Block parsing — the `inode_hash_lock` wall removed.** Read the inode table directly instead of one `iget` per inode: **17.4M obj/s warm (10.4×)**, and with an explicit readahead window **1,420,664 cold at 99% of an NVMe stripe — parity with the userspace device scanner** |
| [`docs/cold-on-fast-storage-2026-08-16.md`](docs/cold-on-fast-storage-2026-08-16.md) | **Cold, on NVMe — a retraction.** Cold is latency-bound for Option 2 and scales 3.6× with threads; Option 1 saturates 93% of the device with one thread. "Cold is a tie" was an artifact of 190 MB/s storage |
| [`docs/option-comparison.md`](docs/option-comparison.md) | The two MDT approaches side by side, with measurements |
| [`docs/throughput-test-plan.md`](docs/throughput-test-plan.md) / [`docs/throughput-results-2026-08-06.md`](docs/throughput-results-2026-08-06.md) | The benchmark that set the build order: 705k vs 105k objects/sec |
| [`docs/upstream-survey.md`](docs/upstream-survey.md) | What already exists in `lustre-release` and what LFU must build |
| [`docs/filter-levels.md`](docs/filter-levels.md) | **Filters — all 34 `lfs find` predicates, per scanner, with a cost tier each.** Why `--size`/`--blocks` are tier 1 and not tier 0, and what "unknown" means on an MDT-only scan. Implemented for both device backends 2026-08-17 |
| [`docs/open-questions.md`](docs/open-questions.md) | Resolved and live design questions |
| [`docs/reference/`](docs/reference/) | Source PDFs |

## Our assignment

Build the **server-based target scanner**: traverse MDT namespace metadata
directly on the server, replacing client-side `lfs find` traversal for the
initial rollout.

All scanners get built (review consensus, 2026-08-06); the sequencing was set
by measurement:

| | Scanner | Status |
|---|---|---|
| 1 | **ldiskfs device scanner** — userspace, libext2fs | **Prototype in `src/`, 61/61 tests**, measured **705k inodes/s** cold-cache on a 12M-inode MDT; **2026-08-17: the `lfs find` filter vocabulary implemented** — 33 of 34 predicates, tier-ordered, with a demand mask |
| 1 | **ZFS device scanner** — userspace, libzpool, snapshot-first | **Prototype in `src/`, 16/16 tests** against a synthetic MDT-like dataset (`make zfs`); shares the same filter compiler |
| 2 | **OSD API scanner** — in-kernel, `dt_it_ops`, all backends | Prototype scanner end-to-end (enumerate → attrs → ring → userspace) at ~796k obj/s on a live MDT; **2026-08-15: parallel enumeration measured — ldiskfs 2.03M obj/s, ZFS 561k (now faster than the ZFS device scanner), concurrent with LFSCK**; **2026-08-16: block parsing — 17.4M obj/s warm and cold parity with the device scanner (99% of an NVMe stripe)**; **2026-08-17: filter pushdown — the same evaluator compiled into `lfu_ring.ko`, tier 1 served from the mapped inode-table block via `rec(DORA_XATTR)`; testable halves tested, kernel side not yet built in a lab** |

## Status

Two working scanner prototypes (`make` / `make zfs`), throughput benchmarked on
the lab cluster, designs reconciled with the 2026-08-05/06 review thread
(Blagodarenko, Day, Dilger).

Live issues worth attention, in `open-questions.md`. None is stated in the source
documents; all are analysis against them:

- **LMR duplicate objects** — LMR (2.19+) mirrors inodes across MDTs, so a per-target scan yields
  **duplicate FIDs** after merge. Every `count`/`sum`/`histogram` aggregate
  over-counts silently, and per-object consumers act twice.
- **WBC invisible metadata** — WBC (2.19+/2.20) holds new metadata in client RAM indefinitely. No
  device scan can see it, which breaks the HLD's "stale by tens of seconds"
  consistency argument.
- **Consumers ship before LFU** — PCC-RO, Trash Can and FLR-ECRO all ship in **2.18**, a release before
  LFU. Each will grow its own scanner first. Structuring those tools as
  would-be LFU consumers now is cheap; after 2.18 it's a rewrite.
- **Torn metadata on a live device** — the HLD accepts *stale* metadata when scanning a live ldiskfs device
  but doesn't address *torn* reads.
- **Does the target survive real filters** — the 1M obj/s/MDT target implies ~1 KiB/object, covering inline
  attributes only — yet **xattr regexp** is an advertised filter dimension.
- **Kernel-side encoding** — no kernel-space FlatBuffers/MessagePack encoder exists, and the
  format freezes long before the kernel scanner needs one.
- **Index priority** — requirements page ranks MDT indexes **High**; HLD defers them. LUG
  slide 22 sides with the HLD.
