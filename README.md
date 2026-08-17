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

## The command

`lfind` is the command; the three backends are separate binaries only because a
host that has just one device library must still be able to build the backend it
can. `lfind` picks one from the target and `exec`s it:

```sh
lfind [options] [filters] <target>

lfind --type f --mtime +30d /dev/sdb          # unmounted ldiskfs, or an image
lfind --blocks +1G pool/mdt0@snap            # unmounted ZFS, or a snapshot
lfind --pool fast /dev/lfu_scan              # a MOUNTED, serving target
lfind --backend zfs --help                   # options and the full filter list
lfind --list-backends                        # which are built here
```

It is **not** `lfs find`: it reads a target directly on the server instead of
walking the namespace from a client, so an MDT-only scan has `lfs find --lazy`
semantics and a size filter can answer *unknown* as well as yes and no — see
[Filters](#filters).

| binary | target | reads |
|---|---|---|
| `lfind` | — | the front-end; chooses one of the three |
| `lfind-ldiskfs` | `/dev/sdb`, `mdt.img` | an unmounted ldiskfs target, via libext2fs |
| `lfind-zfs` | `pool/dataset[@snap]` | an unmounted ZFS target, via libzpool |
| `lfind-kmdt` | `/dev/lfu_scan` | a mounted, serving target, via the `lfu_ring` module |

The reference is the man page,
[`Documentation/man8/lfind.8`](Documentation/man8/lfind.8) — upstream's path and
macro style, so it can be submitted as it stands. Read it from the tree with
`man -l Documentation/man8/lfind.8`. It documents the backend choice, every
option and filter, the three outcomes of a size filter, and the exit statuses;
`lfind --help` is the short form of the same thing.

## Building and installing

Each backend needs its own device library, and no host has all of them — the MDS
build hosts have no ZFS headers, a workstation may have no libext2fs — so the
targets are separate and `all` is the front-end plus ldiskfs:

```sh
make                          # lfind + lfind-ldiskfs        (libext2fs)
make zfs                      # lfind-zfs                    (libzpool)
make kmdt                     # lfind-kmdt                    (no library)
make test test-zfs            # 76 + 16 checks, plus tests/filter_eval_test.sh

sudo make install             # what this host built, into /usr/sbin, + man8
make install DESTDIR=$RPM_BUILD_ROOT prefix=/usr    # staged, for packaging
```

`install` installs the binaries that exist in `build/` rather than depending on
`all`, because a hard dependency would fail on every real machine; it refuses if
nothing has been built. Front-end and backends land in the same directory, which
is how `lfind` finds a backend without a compiled-in path — `LFIND_LIBEXEC`
overrides that, and a build tree works uninstalled for the same reason.

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
| **Filter evaluation** | userspace, after the record is read | **in kernel, before the ring**<br>*same evaluator source, both builds* | — |
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
every lab. **Rates from different labs are not comparable to each other** — one
configuration measured 1.6× apart across two of them, a known and still
unexplained gap; the sound comparisons are within a single table.

**The warm rows are understated.** Every one of them ran at the default
`lfu_ra_blocks=32`, and that axis was never swept until 2026-08-17: warm, readahead
*costs* — turning it off is **+22% at one thread and +90% at four**, monotonically
across the window range, while the `iget`-path control moves only ~7%
([`docs/warm-readahead-and-cold-2026-08-17.md`](docs/warm-readahead-and-cold-2026-08-17.md)).
Cold it is worth 8× when the device is latency-bound and irrelevant when it is
bandwidth-saturated, so a single static window is wrong in two of three regimes.
The figures above are not restated from the newer lab, whose rates sit 1.6× below
these at identical settings.

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
| [`Documentation/man8/lfind.8`](Documentation/man8/lfind.8) | **`lfind(8)` — the user-facing reference.** Backends, options, all 33 filters, the *unknown* outcome, exit statuses. Written in upstream's `Documentation/man8/` style for submission as-is |
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
| [`docs/filter-levels.md`](docs/filter-levels.md) | **Filters — all 34 `lfs find` predicates, per scanner, with a cost tier each.** Why `--size`/`--blocks` are tier 1 and not tier 0, and what "unknown" means on an MDT-only scan. Implemented on all three scanners 2026-08-17 |
| [`docs/filter-pushdown-measured-2026-08-17.md`](docs/filter-pushdown-measured-2026-08-17.md) | **Filter pushdown, measured.** The kernel side built and run: every predicate agrees with the userspace scanner, the `-blocks +1G` trap reproduced on a real MDT, and a rejecting tier-0 filter is **8% faster than no filter at all** |
| [`docs/xiong-68020-filter-measured-2026-08-17.md`](docs/xiong-68020-filter-measured-2026-08-17.md) | **LU-20591's filter (68020) against ours**, one box, one MDT image. Their filter is worth +26% to them against our +12%; their absolute rate is 6–7× lower; and on an MDT their `--size` selects on the inode's zero, so `--size +1G` finds nothing and `--size -1M` includes a 1.5 GiB file |
| [`docs/zfs-tier1-measured-2026-08-17.md`](docs/zfs-tier1-measured-2026-08-17.md) | **Tier 1 on a live ZFS MDT — built and run.** The whole `lfs find` vocabulary now works on a *mounted, serving* ZFS target: 14 of 14 filters agree with the userspace scanner as FID sets, and a predicate reading an xattr for every one of 100,112 objects costs **1.6%** (27% on ldiskfs). Tier 2 proved unreachable there, with a `zdb` dump showing why |
| [`docs/warm-readahead-and-cold-2026-08-17.md`](docs/warm-readahead-and-cold-2026-08-17.md) | **Warm readahead costs, and cold the filter is free.** `lfu_ra_blocks=32` is the wrong default warm — off is +22% at 1 thread, **+90% at 4** — while cold a tier-1 predicate doing 302k xattr lookups costs nothing |
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
| 2 | **OSD API scanner** — in-kernel, `dt_it_ops`, all backends | Prototype scanner end-to-end (enumerate → attrs → ring → userspace) at ~796k obj/s on a live MDT; **2026-08-15: parallel enumeration measured — ldiskfs 2.03M obj/s, ZFS 561k (now faster than the ZFS device scanner), concurrent with LFSCK**; **2026-08-16: block parsing — 17.4M obj/s warm and cold parity with the device scanner (99% of an NVMe stripe)**; **2026-08-17: filter pushdown — the same evaluator compiled into `lfu_ring.ko`, tier 1 served from the mapped inode-table block via `rec(DORA_XATTR)`; built and run on a lab MDT, 3.59M obj/s unfiltered and 3.88M with a rejecting tier-0 filter, every predicate agreeing with the userspace scanner**; **later that day: tier 1 on osd-zfs too — served from the SA xattr nvlist the iterator already unpacks; built and run on a second lab, 14 of 14 filters agreeing with the userspace scanner and tier 1 costing 1.6% there against 27% on ldiskfs** |

## Filters

`lfs find`'s vocabulary is closed: **34 predicates**, of which 33 are answerable
from an MDT — the `--maxdepth`/`--mindepth` pair is what a flat scan cannot answer
at all. All 33 work on **every** scanner as of 2026-08-17, from one source
([`docs/filter-levels.md`](docs/filter-levels.md)):

| | where it lives |
|---|---|
| the parser — `lfs find` syntax → `struct lfu_filter` | `src/lfu_filter.c`, userspace only |
| the evaluator — tier 0, tier 1, the xattr decoders | `src/lfu_filter_eval.c` — linked by the device scanners, `#include`d into `lfu_ring.ko` |
| the compiled filter, and the kernel ioctl payload | `src/lfu_filter.h` — a fixed array of fixed-size predicates, bounded by construction |

Because it is one evaluator, the scanners cannot disagree by design, and do not in
practice: twelve filters run through the kernel and through the device scanner
against the same device agree on all twelve, comparing FID *sets* rather than
counts.

**Cost, measured on a 302,122-object MDT** — the surprise is the sign on the
second row ([`docs/filter-pushdown-measured-2026-08-17.md`](docs/filter-pushdown-measured-2026-08-17.md)):

| filter | obj/s | vs no filter | xattr lookups |
|---|---|---|---|
| no filter | 3,587,401 | — | — |
| `--type f` *(tier 0, matches ~all)* | 3,572,170 | −0.4% | `inline=0` |
| `--uid 4242` *(tier 0, matches 0)* | **3,884,601** | **+8.3%** | `inline=0` |
| `--blocks +1G` *(tier 1, via SOM)* | 2,775,551 | −22.6% | `inline=4,021` |
| `--name 'zzz*'` *(tier 1, via linkea)* | 2,632,343 | −26.6% | `inline=302,018` |

A tier-0 predicate that **rejects** is faster than no filter at all, because the
object never enters the ring. A pure tier-0 query opens no xattr at all. And the
cost of a tier-1 predicate scales with **how many objects carry the attribute**,
not with the object count — most of this namespace has no SOM or LOV, and "not in
the inode, no external block" is a free `-ENODATA`.

Two corrections the filter work forced:

- **`--size`/`--blocks` are tier 1, not tier 0.** An MDT inode's `i_blocks` counts
  the inode's own blocks, not the file's; `trusted.som` is the only number the MDT
  holds. Measured on a real MDT: the inode-based test matched **0 of 302,122
  objects** where the SOM-based one found the 1.5 GiB file. An MDT-only scan is
  `lfs find --lazy` semantics exactly, and a size filter has a third outcome —
  *unknown* — which measured zero here because SOM is on by default in 2.17.
- **Cold, a tier-1 predicate is free.** `--name` did 302,018 xattr lookups at the
  no-filter rate, where warm it cost 27%: the attribute is in a block the scan is
  already reading, so tier 1 is a CPU cost, visible only when CPU-bound.

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
