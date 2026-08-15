# LFU architecture

**Source of truth: `reference/lfu-hld.pdf` — "Lustre Find Utility (LFU)
Architecture", Andreas Dilger, v0.1, 2026-04-03**, with
`reference/lug2026-lustre-218-and-beyond-dilger.pdf` slides 20–22 (LUG 2026,
2026-04-28) as the public summary. Target release **Lustre 2.19+ (TLC)**.

This document summarises that design and records analysis, gaps and risks
against the v2.17 tree. Where it disagrees with the HLD it says so explicitly.

> **Note.** An earlier version of this file proposed a kernel-first architecture
> built on the OSD otable iterator. The HLD makes the *initial* scanner a
> **userspace libext2fs block-device reader**, with the OSD/kernel path as a
> later alternative. That is a better staging decision than the one proposed
> here, and this document has been rewritten to follow it. See §6.

## 1. The core abstraction: three stackable module types

Everything in LFU is a module operating on an **Object Stream** — a sequence of
FID-identified objects (essentially on-disk inodes) with optional attributes.

| Type | Role |
|------|------|
| **Input Scanner** | Produce an Object Stream from a source (MDT, OST, Changelog, index, raw stream file) |
| **Filter Rule** | Consume one or more Object Streams, produce another; matching, merging, aggregation |
| **Output Format** | Consume an Object Stream, render it (text, pathnames, JSON, direct consumer ingest) |

Modules stack. A pipeline is a chain of them, and the same scan can feed several
Output Formats at different points in the chain.

Two design points that fall out of this and are easy to miss:

- **Merge is a Filter Rule capability**, not a separate transport layer. "Merge
  the output from multiple Input Scanner modules into a single object stream" is
  just another filter. This is what makes multi-MDT scanning composable rather
  than a special case.
- **Raw Write / Raw Read** — the Object Stream can be written to a file by an
  Output Format module and re-read by an Input Scanner module. Scans become
  replayable and pipelines splittable across time and machines. Cheap to build,
  disproportionately useful for testing.

### Worked example — LUG 2026 slide 21

The deck's data-flow slide traces one command end to end, which pins down several
things the HLD leaves abstract:

```
lfs find /lfs02 -atime +30d -blocks +1G -projid 1999 -printf %LF
   → LFU: "scan: all MDTs, filter: atime, blocks, projid, output: FID"

  MDT0                      MDT1
  ldiskfs parallel scanner  ldiskfs parallel scanner
        │                         │
  atime > 1 month           atime > 1 month          ← filter runs per-MDT,
  blocks > 1GB              blocks > 1GB               at the source
  proj 1999                 proj 1999
        └───────────┬─────────────┘
             Split/Merge Server PtlRPC Bulk          ← splits request to MDTs,
                     │                                 merges reply streams
              Client PtlRPC Bulk
                     │
             Userspace Ring Buffer
                     │
              "lfs find" LFU module                  ← FIDs only, or add
                                                       pathnames at this point
```

Three details worth extracting:

- **Merge is server-side in the target deployment.** A Split/Merge module
  co-located with the server PtlRPC bulk transport fans the request out to MDTs
  and merges the replies. It is still "just" a Filter Rule module (the deck lists
  *aggregate streams*, *fork stream* and *PtlRPC transport* among Filter Rule
  types), but its home is the server. Early phases without PtlRPC merge in
  userspace by necessity; that is a staging artefact, not the end state.
- **The ring buffer sits on the client too.** The kernel→userspace boundary here
  is the client's PtlRPC bulk module feeding a userspace ring buffer, not only
  the OSD export. The HLD's insistence on "the same Kernel API for Object Stream
  as the OSD" is what makes one mechanism serve both.
- **Only FIDs cross the wire**; pathnames are attached at the very last stage, by
  the Output Format module. Consistent with pathname generation being excluded
  from the performance target.

### Attribute masks

Input Scanners accept a mask of attributes required by downstream modules, so
the stream carries only what is needed. The mask distinguishes **required** from
**optional** attributes — e.g. return a pathname if the source has one cheaply
(namespace scan), omit it if not (a FID-only index). Downstream modules must
therefore tolerate absent optional attributes rather than assuming a fixed record
shape.

## 2. Object Stream format

FlatBuffers is the current front-runner, with ProtoBuf and MessagePack also to be
investigated. The stated reason is specific and worth preserving: **field-offset
access without parsing or decoding every object**. With billions of near-identical
records, per-object decode cost dominates, which is also why JSON is rejected for
the wire format (it stays as an Output Format).

The HLD prefers a cross-platform interchange format over a custom binary protocol
*if performance allows* — the custom protocol is the fallback, not the goal.

Extensibility is explicit: the protocol must allow new attributes without breaking
interop with existing modules, and feature availability is negotiated by
**protocol flags, not version numbers**.

> **Analysis.** The kernel-encoder problem I previously raised largely evaporates
> under the HLD's staging: the initial ldiskfs scanner runs *in userspace*, so
> FlatBuffers encoding happens in userspace where the library actually exists.
> It only returns when the OSD API Input Scanner (§6) exports a stream through
> `circ_buf` from kernel context. By then the format is fixed, so the kernel-side
> encoder question should be answered *before* the format is frozen, not after.

## 3. Performance target

> 1 million objects/sec/MDT, assuming ≥1 GiB/s read from the MDT device,
> **exclusive of pathname generation**. Scaling in parallel across all MDTs/MDSes.
> Upper bound ≈ **1 hour for a full scan of a maximally-populated 4-billion-object
> ldiskfs MDT**.

Two things to carry forward:

- 1M obj/s/MDT at 1 GiB/s implies a ~1 KiB average read per object — which is
  **exactly one default MDT inode**: `mkfs.lustre` uses 1024 B inodes for MDTs
  at ≤16 stripes (`libmount_utils_ldiskfs.c:883-890`) precisely so LMA, LOV and
  linkea fit inline. So the target is achievable, with no headroom: one
  sequential inode read per object and nothing else. Any filter needing an
  external EA block adds a random read and falls off it. Wide-striped
  filesystems (>59 stripes → 512 B inodes, layouts always external) miss it
  structurally. See `design-ldiskfs-scanner.md` §4.3 and §11.
- **Pathname generation is explicitly excluded from the target.** Path resolution
  is an Output Format concern, priced separately. This settles what was previously
  an open question — see `open-questions.md` *Path resolution priced separately*.

## 4. Use cases driving the design

FLR/EC delayed resync · flash→HDD tier migration · PCC-RO cache eviction ·
Trash Can Undelete purge · filesystem usage reports (per-user/group/project
histograms of age and space).

The reporting use case is why Filter Rules include **aggregation operators** —
`largest`, `smallest`, `in list`, `range`, `histogram`; the deck adds `min (+list)`,
`max (+list)`, `count`, `sum` — evaluated *at the source* so attributes never
cross the wire. Histograms from multiple sources must merge efficiently. This is
a genuine architectural requirement, not a reporting nicety: it is the difference
between shipping a billion records and shipping a bucket array.

### Filter and output capability set (LUG slide 20)

**Filter by:** attributes (ranges) · IDs (range, list) · **xattrs (regexp)** ·
MDT/OST (range, list) · pool. Plus selective attribute pass-through to upper
modules — path, FID, attrs, everything.

**Output to:** text filename/FID list, `printf` · JSON, CSV, BSON, Parquet ·
FlatBuffers, MsgPack · direct binary import into consumer utilities.

> **Note the xattr regexp filter.** This confirms that filtering on non-inline
> xattrs is in scope, which is precisely the class of filter that breaks the
> ~1 KiB/object budget implied by the performance target. See
> `open-questions.md` *Does the target survive real filters*.

## 5. No external database

LFU's efficient operation *must not depend* on an external database. The argument
in the HLD is resource-economic: a database sized to hold all filesystem metadata
needs hardware comparable to all the MDTs/MDSes combined, which would be better
spent as more MDTs — making both LFU and the filesystem faster instead of
stranding capacity in a side service. Keeping such a database current is also
noted as a perennial problem.

Consumers may still have their own databases (RobinHood), and the preferred
integration is an Output Format module feeding them directly.

## 6. Server-side: two scanner paths, staged

### 6a. ldiskfs Device Input Scanner — **the PoC path**

> **Detailed design: [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md).**
> **Revised 2026-08-06:** this is now the first target, not the alternative.
> A working prototype exists; the throughput benchmark
> ([`throughput-results-2026-08-06.md`](throughput-results-2026-08-06.md)) measured it at
> **705k inodes/s** against **105k objects/s** for the §6b iterator path on
> identical hardware. It is also the only option that works on **old servers
> with no LFU kernel support** and for **offline analysis of an unmounted MDT
> or snapshot**. See [`option-comparison.md`](option-comparison.md).

Scans the MDT/OST block device **directly in userspace via libext2fs**, following
`e2scan` and Lester. Runs independently of the MDS/OSS service; needs only
read-only access to the block device. Reads at device bandwidth.

Its decisive practical advantage: **it works on unmodified old servers.** No
kernel changes, so LFU can be deployed against an existing filesystem — which is
what makes the "no flag day" rollout real rather than aspirational.

**Consistency caveat (accepted in the HLD):** on-disk metadata may lag in-memory
state by up to tens of seconds, affecting only objects created/modified/removed
just before being scanned. A scan is not atomic with respect to concurrent
namespace changes, and scanning a snapshot would not help since it would miss
recent changes anyway. Target consumers care about aggregates and bulk lists,
where a few inconsistent objects don't change the answer.

> **Risk to verify.** Staleness is the acknowledged caveat; *torn* metadata is
> not discussed. Reading a live read-write ldiskfs device can observe blocks
> mid-write and group descriptors / bitmaps inconsistent with the inode table,
> not merely stale. `design-ldiskfs-scanner.md` §4.1 and §8.2 answer the
> "which structures" half — inode bitmap, inode table and EA blocks only; no
> block bitmaps, extent trees, directory blocks or journal — and specify
> validation, bounds-checking and skip-counting. The measurement half (a live
> write-heavy scan with the skip counter watched) is still outstanding.

### 6b. OSD API Input Scanner — **the second wave, and the only path to WBCFS**

> **Detailed design: [`design-osd-scanner.md`](design-osd-scanner.md).**
> Selected by Artem on 2026-08-05 as *the* MDT scanner; **resequenced on
> 2026-08-06** after review and the throughput benchmark. Both scanners get built
> (Dilger: "in the end we will want both of these") — this one lands after the
> §6a device scanner, because it is the slower path today (measured throughput) and because the
> Object Stream format should be frozen by working code before kernel work
> starts. It is not optional — it is the only route to WBCFS, to live in-memory
> metadata, and to in-kernel filter pushdown (§6c compares the three scanners).
> The §6a API must not preclude it.

Interfaces with the running OSD (`osd-ldiskfs`, `osd-zfs`, `osd-wbcfs`) and has
it perform the scan, **reusing the existing OI Scrub / LFSCK device scanner**.
The HLD notes LFSCK may itself be restructured as an Object Stream consumer.

The decisive advantages, three of which are backed by measurements from the §6a
prototype (`design-ldiskfs-scanner.md` §17): metadata is read in memory and is
never torn; the OSD already knows which of its objects are internal; and one
implementation covers every backend.

The main new engineering is that **the otable iterator returns FIDs only** — in
all three OSDs — so LFU must extend it to carry attributes without entering the
object layer per object. See `design-osd-scanner.md` §3.

| Advantage | Cost |
|---|---|
| Metadata is up to date (read from memory, not disk) | Extra overhead processing objects consistently inside OSD code |
| No direct block-device access → better security | Kernel→userspace transfer of large structured volumes |
| One API across all OSD backends | Likely forces basic attribute filtering *into the kernel* to cut volume |
| Direct device access is reasonable for ldiskfs's static layout, but far more complex for ZFS and incongruent with WBCFS | New OSDs must implement it |

This is where the tree survey pays off: `dt_otable_features` is already
implemented by all three OSDs (`osd-ldiskfs/osd_scrub.c:2760`, `osd-zfs/`,
`osd-wbcfs/`) and consumed only by LFSCK. The OSD API scanner is largely a matter
of exposing it, not building it.

### 6c. ZFS Device Input Scanner — **a third scanner** [revised 2026-08-06]

> **Detailed design: [`design-zfs-scanner.md`](design-zfs-scanner.md)** (sketch,
> no prototype).

> **This section previously argued the opposite** — that ZFS should be served
> only by §6b, because ZFS has "no libext2fs equivalent and no sequential table
> to walk". **That reasoning was wrong on the facts.** osd-zfs's own object-table
> iterator is `dmu_object_next()` over the objset (`osd-zfs/osd_scrub.c:1672`):
> a sequential walk of the dnode array in object-ID order, structurally the same
> thing as walking the ldiskfs inode table. A userspace ZFS scanner is tractable,
> and it is now planned.

What the earlier argument got right, and what survives: **zester's approach is
not viable.** It shells out to `zdb -dddd` per dataset and parses the text dumps
— Python 2, Lustre 2.8 / ZFS 0.6.5 era, regular files only, no directories, no
DNE, and knowingly over-reports sizes because it ignores stripe extent offsets.
Read it for its MDT↔OST join logic and size-reconstruction traps before the
OST-side module is designed; do not build on it. The viable route links
`libzpool` (what `zdb` itself uses) rather than parsing `zdb` output.

The per-object recipe mirrors §6a closely — `dmu_object_next()` → dnode bonus →
SA attributes → unpack the `SA_ZPL_DXATTR` nvlist → `trusted.lma` → FID — so
everything above the device layer (classification, cost tiers, filter pushdown,
record format, the `lfs find` oracle) is shared with §6a rather than rewritten.

**One capability neither ldiskfs scanner has.** ZFS snapshots are atomic and
near-free, so scanning a snapshot observes every object at one txg. That removes
torn reads, the commit window, the validation heuristics *and* begin-to-end scan
skew — the last of which is documented elsewhere in these records as unfixable
for both ldiskfs options. Precisely: a snapshot improves *internal consistency*,
not *freshness*.

**Still true:** §6b remains the only route to WBCFS, to live in-memory metadata,
and to in-kernel filter pushdown. And **the throughput results do not transfer** —
705k inodes/s and 105k objects/s are both ldiskfs figures; ZFS needs its own run
of `throughput-test-plan.md`, for this scanner and for ZFS OI Scrub as the §6b
proxy.

### Kernel API for Object Stream

The HLD names the Linux **Circular Buffer Interface (`circ_buf.h`)** for
kernel→userspace stream export — lockless, zero-copy, near-memory-speed. Not a
new mechanism to invent.

### Changelog: an input, not a casualty

Changelog is retained as an **Input Scanner Module**, using existing server- and
client-side interfaces, for monitoring ongoing modifications. Additionally a new
**Changelog Output Filter Module** on the MDS would filter changelog events by
*attribute* (created by UID 1000, files over 1 TB), which is not possible today —
changelog can only be configured by *operation* type.

So "replaces Changelog" from the epic was misleading in both directions: LFU
neither replaces changelog nor merely tolerates it. It absorbs it as a source and
gives it a capability it lacks.

### Index Input Scanner — future

Indexes store FIDs (and possibly the indexed attribute, for ordering); other
attributes are populated from the objects on demand.

- **Oldest atime index** — FIDs in `llog` files named by atime range; a file rolls
  over at ~1M FIDs or ~1h of atime spread; FIDs cancelled on delete or atime
  change beyond the file's range; empty files deleted.
- **Largest file index** — indexed on `i_blocks` (space used), *not* `i_size`
  (last-byte offset), since space is what needs attention. No "smallest files"
  case, so indexing only files above ~1% of filesystem capacity may suffice.

The HLD notes indexes should preferably be maintained as part of core MDS/OSS
operations so they update atomically with the operation, like Changelogs.

### Server Bulk RPC Filter Rule Module

Exports Object Streams from MDS/OSS to a client node, similar to changelog access,
with server-side authentication and result filtering so the stream contains only
objects the user may see.

## 7. Client-side

| Module | Notes |
|---|---|
| **Lustre Namespace Input Scanner** | Directory traversal in userspace; extract from **LU-17814** ("`lfs find` to scan with multiple threads" — this is `liblustreapi_pfind.c` in tree), using `ioctl(LL_IOC_MDC_GETINFO_V2)` for attributes. Works on old clients. **Cheaper than it looks — verified in tree (§7a).** |
| **`lfs find` Filter Rule + Output Format** | Reimplement `lfs find` on LFU APIs — early feedback on the API, and avoids leaving `lfs find` as technical debt |
| **POSIX Input Scanner** | `statx()`-based traversal of non-Lustre filesystems, for PCC-RO and TCU; likely folded into the namespace scanner rather than duplicated |
| **Client Bulk RPC Filter Rule** | Attaches to the server-side module; Object Stream via **bulk RDMA** direct to the client, subject to POSIX UID/GID/ACL, filesets and nodemaps. Same kernel Object Stream API as the OSD, for uniformity. |

Once the client bulk RPC module exists, `lfs find` can push search requests to
multiple servers in parallel instead of scanning locally. The HLD cites server
offload of namespace scanning as a proven IO500 `find` win.

**Starting client-side is deliberate.** The namespace Input Scanner gives a
working end-to-end pipeline on unmodified clients and servers, which shakes out
the API and data structures before any kernel work is committed to. Endorsed
independently by Dilger (2026-08-06): the device scanner *and* the client-side
traversal are the first wave, and together they are "enough to implement a
variety of useful tools" before any OSD-API or LNet-transport work.

### 7a. The client-side scanner is mostly already in tree **[verified]**

Checked against `../lustre-release` on 2026-08-06 — the parallel traversal this
module needs already exists and is already public API:

| Piece | Where | Status |
|---|---|---|
| Threaded work-queue traversal | `lustre/utils/liblustreapi_pfind.c` (3 759 lines; Farrell/DDN 2024) — `find_worker()` :3225, `find_work_queue_init()` :3277, `pthread_create` :3299 | in tree |
| Attribute fetch via the ioctl | `LL_IOC_MDC_GETINFO_V2` at :319, :326 | in tree |
| `statx()` fallback for non-Lustre | `struct statx` at :137-142, `convert_lmd_statx()` :237 | in tree |
| Parallel dispatch | `llapi_find_with_cb()` → `parallel_find()` when `fp_thread_count > 1` (`liblustreapi.c:3455-3464`) | in tree |
| User-facing knob | `lfs find --threads N` (`lfs.c:7231`, default from `calculate_default_thread_count()`) | in tree |
| **Callback hook** | `llapi_find_cb_t` (`lustreapi.h:491`) and `llapi_find_with_cb()` (`lustreapi.h:534`) are **exported** | in tree |

The consequence is that this module is not a new crawler. `llapi_find_with_cb()`
already takes per-entry callbacks; a client-side Input Scanner is an
implementation of `llapi_find_cb_t` that emits Object Stream records instead of
printing, driven by the existing thread pool. The `statx()` fallback also means
the **POSIX Input Scanner is the same module with a different attribute source**,
as the table above anticipated — it should not be built twice.

## 8. Interoperability

- New `OBD_CONNECT2_LFU` connection flag negotiates server-side scanning at
  client connect time.
- Old servers: the ldiskfs device scanner works with no kernel changes at all.
- Old clients: the namespace scanner works via long-standing `lfs find` APIs —
  no faster than today's `lfs find`, but lets old clients use LFU APIs.
- Feature availability signalled by **protocol flags, not version numbers** —
  one of the stated reasons for an extensible binary format over monolithic
  structures.

## 9. Release-context interactions

LFU targets 2.19+. Several features on the same roadmap interact with it, and
none of the three source documents mentions the interaction. All of the below is
analysis, not from the documents.

### 9a. LMR mirrors inodes across MDTs — duplicate objects in the stream

**Lustre Metadata Redundancy (LMR, 2.19+)** mirrors metadata across MDT devices:
LMR-FID (LU-16742, TLC) provides "infrastructure for inodes mirrored to multiple
MDTs", with directory entries carrying multiple FIDs and replicas directly
accessible when an MDT is offline. LMR2 extends this to ROOT, subdirectories and
per-file replication.

A device-level scan enumerates inodes per target. With LMR active, **a mirrored
inode is enumerated once per MDT holding a replica**, so the merged stream
contains duplicates. Consequences:

- `count`, `sum` and `histogram` aggregates over-count — silently, and by an
  amount that varies with mirror policy.
- Consumers acting per-object (HSM archive, tier migration, trash purge) process
  the same file more than once.
- Dedup has to happen in the Split/Merge module, on FID — which means merge is no
  longer a pure stream concatenation and needs either sorted input or state
  proportional to the mirrored working set.

Neither LMR nor a "replica" flag appears in the LFU record layout discussion.
Since both features are 2.19+ and share an author, this is likely known but
unwritten — worth confirming rather than assuming.

### 9b. WBC holds metadata that no device scan can see

**Metadata Writeback Cache (WBC2)** — slide 4 lists it under 2.20, slide 26 says
2.19+ — creates directories and files in client RAM with no RPCs at all, flushing
"the rest of the tree in background by age or size limits". `osd-wbcfs` is
already in the v2.17 tree.

The HLD's consistency argument is that on-disk state lags in-memory state "by
possibly tens of seconds", affecting a tiny fraction of objects. **WBC breaks that
premise.** Cached metadata is not merely uncommitted on the server — it has never
reached the server, and is held on the client for an unbounded interval governed
by flush policy. A device scanner cannot see it by any mechanism.

For aggregate reporting this is tolerable and arguably invisible. For consumers
that must not miss files — trash cleanup, tier migration, HSM archival — the
question is whether "LFU does not see unflushed WBC state" is an acceptable
documented limitation or requires a flush interlock. That should be decided
deliberately, not discovered.

### 9c. Named consumers ship *before* LFU exists

LFU is 2.19+. Three of its named consumers land in **2.18**:

| Consumer | Ticket | Slide note |
|---|---|---|
| PCC-RO | LU-10499 | Remaining 2.18 work: "**Userspace tool for cache space management, removal of old files**" |
| Trash Can / Undelete | LU-18465 | "Complex cleanup policies run in **userspace**" |
| FLR-ECRO | LU-10911 | Delayed redundancy — resync needs a scan of recently-written files |

Each needs exactly the scan LFU is meant to provide, a release before LFU exists.
Each will therefore ship its own scanner.

This inverts the framing in the requirements page, which presents "consumers
re-implement scanning logic" as an existing problem LFU will solve. It is also an
*accruing* problem: by the time LFU lands there will be more bespoke scanners
than there are today, and LFU's consolidation story becomes retrofitting rather
than greenfield adoption.

Actionable version: the PCC-RO and TCU cleanup tools are being written now. If
their scan logic is structured as a would-be LFU Output Format consumer — even
against a stub — the later migration is mechanical instead of a rewrite. That is
a cheap intervention available only before 2.18 ships.

### 9d. Adjacent infrastructure worth reusing

- **Nodemap / RBAC / fileset** work is well advanced (LU-19975 RBAC on default
  nodemap, LU-19884 / LU-19963 nodemap RBAC ops, LU-18357 multiple read-only
  filesets). The Server Bulk RPC Filter Rule Module should build on this rather
  than invent access control — see `open-questions.md` *Access control granularity*.
- **`llapi_*()` consolidation** (slide 18) — "move core logic out of `lctl`,
  `lfs`, configuration scripts into shared library code" — is the same direction
  LFU's `lfs find` reimplementation pushes. Aligned effort.
- **`rustreapi`** (LU-19561, TLC/WC) — a Rust interface is under development.
  Relevant to how LFU's userspace modules and third-party API get bound.
- **`lfs fid2path` for OST object FIDs** (LU-13527) — directly relevant to
  pathname output from OST-side scans.

## 10. Testing

From the HLD:

- MDT and OST device scans report all files/objects stored therein
- Directory tree scans report all files and directories therein
- Object Stream encode/decode/structure, including cross-release compatibility
- Filter Rule tests per module — existing `lfs find` test cases already cover
  much of that module
- Aggregate Filter Rule accuracy: min, max, count, sum, histogram
- Output Format structure and rendering per module, including **FID → pathname
  generation**

The lab cluster (`../lab`) with its MDS failover setup is the natural place for
scan-restart and cursor-stability testing, which the HLD does not cover — see
`open-questions.md` *Restart, checkpoint and scan identity*.

## 11. Deferred to "future improvements"

Structured Output Formats (JSON, BSON, Parquet) and direct-ingest plugins for
RobinHood/PoliMor/GUFI · internal indexes · **persistent aggregates** — per-
directory min/max/count/sum summaries stored in the filesystem itself, GUFI-style,
updated bottom-up from Changelog, enabling subtree pruning during search. The HLD
suggests integrating with GUFI rather than rebuilding that ecosystem.

## 12. Suggested build order

Not stated as a phase list in the HLD; this is the ordering its dependencies imply.

| Step | Scope | Why here |
|------|-------|----------|
| 1 | Object Stream format + Raw Read/Write modules | Everything else is defined in terms of it; Raw R/W makes the rest testable |
| 2 | Lustre Namespace Input Scanner (from LU-17814) + `lfs find` Filter/Output | End-to-end pipeline on unmodified clients and servers; validates the API cheaply |
| 3 | **ldiskfs Device Input Scanner (libext2fs)** — [detailed design](design-ldiskfs-scanner.md) | The first real performance win; works on old servers. **Measured 705k inodes/s** (throughput benchmark, 2026-08-06). Steps 2 and 3 together are Dilger's first wave — "enough to implement a variety of useful tools" |
| 3b | **ZFS Device Input Scanner (libzpool)** — [detailed design](design-zfs-scanner.md) | Same shape as step 3 behind a shared target-backend interface, so only the "get object id + attrs + LMA" layer is new. Brings ZFS coverage forward without waiting for step 6, and adds snapshot-consistent scanning, which no ldiskfs scanner can offer. Sketch only — two load-bearing facts unverified (§6c) |
| 4 | Aggregate/histogram Filter Rules | Unlocks the reporting use case without new transport |
| 5 | Changelog Input Scanner + Changelog Output Filter | Reuses existing transport; delivers attribute-filtered changelog |
| 6 | OSD API Input Scanner + `circ_buf` kernel export | First kernel work; needs the format frozen. Resequenced here 2026-08-06 on throughput rather than dropped — it is the **only** path to WBCFS, live metadata and kernel-side filtering (§6c), and the iterator-singleton redesign is the work it most needs first |
| 7 | Server/Client Bulk RPC Filter modules + `OBD_CONNECT2_LFU` | Remote scanning, access control, non-root use |
| — | Indexes, persistent aggregates | Independent track (see `open-questions.md` *Index priority*) |

The load-bearing property of this order: **steps 1–5 require no kernel changes.**
