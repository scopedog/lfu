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

All rows below are GCP c3-standard-8 labs, Rocky 9.8, kernel 5.14.0-687.36.1,
Lustre v2_17_55 built from source. Absolute rates are not server-class claims —
the ratios and the mechanisms are what transfer.

### Cold — the number that sizes a real scan

20M objects on a RAID0 stripe of two local NVMe SSDs, **1,397 MB/s** to one
sequential reader. Every row reads the same 19.5 GB, so what varies is how fast
those bytes arrive ([`blockparse`](docs/blockparse-2026-08-16.md),
[`cold-on-fast-storage`](docs/cold-on-fast-storage-2026-08-16.md)):

| ldiskfs, cold | obj/s | bandwidth | device |
|---|---:|---:|---:|
| OSD scanner, singleton `od_otable_it` | 202,376 | 198 MB/s | 14% |
| OSD scanner, `DOIF_PARALLEL` × 1 | 247,762 | 242 MB/s | 17% |
| OSD scanner, `DOIF_PARALLEL` × 16 | 731,452 | 714 MB/s | 51% |
| *block parse alone, × 1 — no readahead* | *31,689* | *31 MB/s* | *2%* |
| OSD scanner, block parse + readahead, × 1 | 1,119,013 | 1,093 MB/s | 78% |
| **OSD scanner, block parse + readahead, × 4** | **1,420,664** | 1,387 MB/s | **99%** |
| userspace ldiskfs device scanner, `-j 4` | 1,439,300 | 1,318 MB/s | 94% |

Against the HLD's **1 hour / 4 billion objects**: 0.78 h in-kernel, 0.77 h in
userspace. Both meet it, and the ratio between the two options is **1.01** —
which retires "Option 1 takes the device and Option 2 cannot reach it". The gap
was `ldiskfs_iget()`, not the kernel.

Removing `iget` on its own is a regression cold: `__ldiskfs_get_inode_loc()` had
been issuing a plugged 32-block readahead window around every inode-table block
and `sb_bread()` does not. The win is *parse instead of iget **and** bring your
own readahead*; window size is the lever, and 32 → 256 blocks takes one thread
from 27% to 78% of the device.

### Warm — per-object CPU cost

2M objects, MDT mounted and serving, medians of three, OI verification off.
Warm rates at this scale are a CPU measurement, not a scan estimate: the inode
table fits in page cache and a production MDT's never will.

Parallel enumeration, both backends, speedup against each backend's own
singleton ([`parallel-osd-measured`](docs/parallel-osd-measured-2026-08-15.md)):

| Enumerators | ldiskfs obj/s | × | ZFS obj/s | × |
|---|---:|---:|---:|---:|
| singleton `od_otable_it` | 852,921 | 1.00 | 154,459 | 1.00 |
| private, 1 | 1,247,723 | 1.46 | 193,713 | 1.25 |
| **private, 2** | **2,028,498** | **2.38** | 315,921 | 2.05 |
| private, 4 | 1,795,421 | 2.11 | 463,306 | 3.00 |
| private, 16 | 1,797,035 | 2.11 | **561,509** | **3.64** |

ldiskfs stops at two threads because 83% of eight threads is spinning on
`inode_hash_lock` inside `iget_locked()`. ZFS has no single dominant symbol at
any thread count, so it keeps scaling — and at 561k it is now **2.5× the
userspace ZFS device scanner**.

Block parsing removes that lock, ldiskfs only, separate run
([`blockparse`](docs/blockparse-2026-08-16.md)):

| Enumerators | iget path obj/s | block parse obj/s | × |
|---|---:|---:|---:|
| singleton — the control | 746,026 | 732,636 | 0.98 |
| private, 1 | 1,065,581 | 6,873,185 | 6.45 |
| private, 2 | 1,669,530 | 12,048,777 | 7.22 |
| **private, 4** | 1,607,795 | **17,392,147** | **10.82** |
| private, 8 | 1,610,384 | 14,085,190 | 8.75 |

**Peak to peak, 1,669,530 → 17,392,147: 10.4×**, and 23× against the singleton.
`find_inode_fast` and `ldiskfs_xattr_ibody_get` leave the profile entirely. The
curve now peaks at four threads because the box is 31% *idle* at eight — the
work per object is small enough that an 8-vCPU machine cannot keep eight
enumerators fed.

### Head-to-head with LU-20591

Jinshan Xiong's series and ours built as two trees on one machine, against one
MDT image formatted and populated under his build, modules swapped between
rounds ([`upstream-collision-68019`](docs/upstream-collision-68019.md)):

| Warm, 2M objects | obj/s | vs. his API |
|---|---:|---:|
| his — `lctl iterate_objects`, with attributes | 351,074 | 0.58× |
| his — `llapi_obj_iterate()`, no-op callback | 604,487 | 1.00× |
| ours — singleton | 842,146 | 1.39× |
| **ours — private, 2 threads** | **2,074,789** | **3.43×** |

The sharpest result is a non-difference: his bare and attribute-bearing rates
are identical (604,374 vs 604,487), because `mdt_scrub_iter_rec()` calls
`dt_locate()` + `dt_attr_get()` unconditionally for its `S_ISREG()` filter.
Attributes are free from him *because they are already paid for on every
object* — which is exactly why `DOIF_ATTR` under his ioctl helps. His patch set
1 is `Verified: REJECT` in Gerrit and self-described as untested, so these are
"here is what the per-object `dt_locate` costs", not a scoreboard.

### Correctness

Every rate above is accompanied by an order-independent checksum over all FIDs,
and for the block-parse runs a second over every attribute of every object.
Across both backends, 1 to 16 threads, five shard sizes, attributes on and off,
both parse paths, and the singleton baselines: `fidsum a589666c4d4f7123`
(ldiskfs, 2,000,097 objects), `attrsum fca15e310ea825d8`,
`39d945cad6c1b98d` (ZFS) — identical on every run, reproduced across four
separate labs. The raw parse is bit-identical to `ldiskfs_iget()` in both the
FIDs and the attributes, and `tests/blockparse_test.sh` checks the two parsing
functions in userspace against ext4 images written by `mke2fs` and `debugfs`.

LFU also runs **concurrently with a verifying OI scrub** on both backends
(1,476,086 obj/s ldiskfs, 392,560 ZFS) where the singleton path returns −114 on
the same build.

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
| 1 | **ldiskfs device scanner** — userspace, libext2fs | **Prototype in `src/`, 17/17 tests**, measured **705k inodes/s** cold-cache on a 12M-inode MDT |
| 1 | **ZFS device scanner** — userspace, libzpool, snapshot-first | **Prototype in `src/`, 16/16 tests** against a synthetic MDT-like dataset (`make zfs`) |
| 2 | **OSD API scanner** — in-kernel, `dt_it_ops`, all backends | Prototype scanner end-to-end (enumerate → attrs → ring → userspace) at ~796k obj/s on a live MDT; **2026-08-15: parallel enumeration measured — ldiskfs 2.03M obj/s, ZFS 561k (now faster than the ZFS device scanner), concurrent with LFSCK**; **2026-08-16: block parsing — 17.4M obj/s warm and cold parity with the device scanner (99% of an NVMe stripe)** |

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
