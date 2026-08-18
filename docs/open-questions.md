# Open questions

Reconciled against `reference/lfu-requirements.pdf` (Confluence export) and
`reference/lfu-hld.pdf` (Dilger HLD v0.1, 2026-04-03). Resolved items kept with
their answers.

> **Questions are referred to by name, not by number** (changed 2026-08-06 — the
> old `K4`/`M8`/`Q13` labels meant nothing to anyone outside this repo). Each
> heading below is the name; cross-references from the design documents use it
> in *italics*. Module-specific questions live with their module:
> `design-ldiskfs-scanner.md` §15 and `design-osd-scanner.md` §11.

## Resolved

### Changelog is an *input*, not a casualty

The requirements page scopes this to the "Changelog **crawl**". The HLD goes
further: Changelog is retained as an **Input Scanner Module**, and gains a new
**Changelog Output Filter Module** on the MDS allowing filtering by *attribute*
(UID 1000, files over 1 TB) rather than only by operation type — a capability it
does not have today.

The epic's "replaces Changelog" was misleading in both directions. LFU absorbs
changelog as a source and extends it.

### Ordering is opt-in; merge is a Filter Rule capability

Merge is a property of Filter Rule modules ("merge the output from multiple Input
Scanner modules into a single object stream"), with sorting optional. Not a
special transport layer, not a guarantee of the scan.

### Object Stream format: FlatBuffers preferred

The HLD names FlatBuffers as front-runner (ProtoBuf and MessagePack also to be
investigated), for **field-offset access without parsing every object** — the
right reason given billions of near-identical records. A custom binary protocol
is the explicit fallback, not the goal. Extensibility via protocol flags, not
version numbers.

### Path resolution is an Output Format module, priced separately

The performance target is stated "**exclusive of pathname generation**", and
FID→pathname is an Output Format module with its own test requirement. This was
previously *Filter predicate classification*.

Note the interaction with access control (*Access control granularity*): per-user POSIX filtering needs
parent-directory knowledge, so excluding path cost from the scan target does not
exclude it from the *secured* path.

### Merge location

Resolved, and LUG slide 21 pins it down: a **Split/Merge Server PtlRPC Bulk**
module sits on the server, splitting the request across MDTs and merging the
reply streams. So the requirements page's "server-side" was literal — but it is
still a Filter Rule module (the deck lists *aggregate streams*, *fork stream* and
*PtlRPC transport* as Filter Rule types), not a separate transport layer, and it
belongs to the PtlRPC phase.

Early phases without PtlRPC merge in userspace out of necessity. That is a
staging artefact, not the end state — worth being precise about, since an earlier
reading here treated userspace merge as the target design.

### External database

LFU must not *depend* on one; consumers may have their own, ideally fed by an
Output Format module. The HLD's argument is resource-economic: a database sized
for all filesystem metadata needs hardware comparable to all MDTs combined, better
spent as more MDTs.

### Which existing scanners fold in

`e2scan` and Lester are cited as *design precedents* for the ldiskfs device
scanner, not code to absorb. LFSCK/OI Scrub is reused via the OSD API scanner,
and the HLD notes LFSCK "may itself be restructured into an Object Stream
consumer". `lfs find` is reimplemented on LFU APIs explicitly to avoid leaving it
as technical debt.

Still unmentioned: `lustre/utils/libhsm_scanner.c`. Minor.

## Live questions

### LMR mirrors inodes across MDTs; the merged stream will contain duplicates **[new, highest]**

**Lustre Metadata Redundancy (LMR, 2.19+)** mirrors inodes to multiple MDTs
(LMR-FID, LU-16742). A device-level scan enumerates inodes per target, so a
mirrored inode appears **once per MDT holding a replica**. After merge, the
stream has duplicate FIDs.

- `count` / `sum` / `histogram` aggregates over-count, silently, by a factor that
  varies with mirror policy.
- Per-object consumers (HSM archive, tier migration, trash purge) act twice on
  the same file.
- Dedup belongs in the Split/Merge module, keyed on FID — which stops merge being
  a pure concatenation and needs sorted input or state proportional to the
  mirrored working set.

LMR and LFU are both 2.19+ and share an author, so this is plausibly known and
simply unwritten. But no LFU document mentions a replica flag, a primary-replica
rule, or dedup, and the record layout has no field for it.

**Blocks:** record layout, merge module semantics, correctness of every aggregate.

### WBC holds metadata no device scan can see **[new]**

**Metadata Writeback Cache (WBC2**, 2.19+/2.20 — the deck is inconsistent between
slides 4 and 26**)** creates files and directories in client RAM with no RPCs,
flushing in background by age or size limits.

The HLD's consistency argument is that on-disk state lags in-memory state by
"possibly tens of seconds" and affects a negligible fraction of objects. WBC
breaks the premise: that metadata never reached the server at all, and stays on
the client for an interval bounded only by flush policy.

For aggregate reporting, tolerable. For consumers that must not miss files —
trash cleanup, tier migration, HSM archival — this needs to be either a
documented limitation or a flush interlock. Decided, not discovered.

### Index priority: the documents disagree **[leaning resolved]**

- **Requirements page:** MDT-side indexes ranked **High**; desired-UX item 3
  ("near-instantaneous regardless of namespace size") depends on them entirely.
- **HLD:** "Use of Internal Indexes" appears under **"Future Improvements Beyond
  Initial Implementation"**.
- **LUG slide 20** lists indexes among the core bullets, but **slide 22** frames
  the project as *"LFU doesn't need to do everything before it becomes very
  useful — optimized `lfs find` is enough to start"*, with incremental rollout.

Slide 22 sides with the HLD, and that is also the defensible engineering
position: indexes are new persistent on-disk state with their own consistency,
recovery and upgrade story, and a working scanner is what you validate an index
against. Treat indexes as a separate track unless told otherwise — but get it
confirmed, since the requirements page is what the UX promises are written
against.

### Named consumers ship a release before LFU **[new]**

LFU is 2.19+. PCC-RO (LU-10499), Trash Can (LU-18465) and FLR-ECRO (LU-10911)
all land in **2.18**, and each needs the scan LFU is meant to provide. The deck
explicitly lists PCC-RO's remaining 2.18 work as a "userspace tool for cache
space management, removal of old files", and TCU's cleanup policies as running in
userspace.

So each will ship its own scanner first. The requirements page presents
"consumers re-implement scanning logic" as a pre-existing problem LFU solves; it
is in fact still accruing, and LFU's consolidation story is retrofitting rather
than greenfield.

Cheap intervention, available only before 2.18 ships: structure the PCC-RO and
TCU cleanup tools as would-be LFU Output Format consumers, even against a stub,
so migration is mechanical rather than a rewrite. Worth raising now — this window
closes.

### Torn metadata when scanning a live ldiskfs device **[new]**

The HLD accepts *staleness* (on-disk lags in-memory by tens of seconds) and
argues convincingly that it doesn't matter for aggregate-oriented consumers. It
does not discuss *torn* reads: a live read-write device can yield blocks caught
mid-write, and group descriptors or bitmaps inconsistent with the inode table.

e2scan's practical mitigation is to read inode tables and little else. Whether
that holds for LFU depends on which structures the filter set forces it to touch —
and a filter needing non-inline xattrs walks into exactly the blocks most likely
to be in flux.

Wanted: an explicit statement of which on-disk structures the scanner may read,
and a validation run against a live write-heavy filesystem.

**Blocks:** confidence in the primary initial deliverable.

**Widened 2026-08-16 — this is no longer only an Option 1 question.** The OSD
scanner's exemption rested on reading in-memory inodes. Block parsing does not:
on the `DOIF_PARALLEL` ldiskfs path it reads inode-table blocks through the
buffer cache. Those blocks are updated at `ldiskfs_mark_inode_dirty()`, not at
writeback, so the exposure is far narrower than a raw device read — but it is
not nil, and it has not been measured. The raw parse also skips the inode
metadata checksum that `ldiskfs_iget()` verifies, so a corrupt inode is reported
rather than refused (defensible for a scanner whose consumer re-reads before
acting; it belongs in the API contract). The validation run wanted above should
now cover both scanners.

### Does the 1M obj/s/MDT target survive real filters? **[new]**

1M objects/sec at ≥1 GiB/s implies roughly a 1 KiB read per object — about one
inode, assuming sequential inode-table access. That budget covers inline
attributes only. Any filter needing a non-inline xattr (layout for mirror status,
linkea for paths) adds a seek per object and falls off the target entirely.

Since mirror status is a named index attribute and FLR resync is a headline use
case, the gap between "filters that hit the target" and "filters consumers
actually want" needs measuring early.

LUG slide 20 confirms the concern is not hypothetical: **xattrs (regexp)** is an
advertised filter dimension, and an xattr regexp match is the furthest thing from
a 1 KiB inline read.

**Blocks:** whether the headline performance claim holds for headline use cases.

**Confirmed arithmetically 2026-08-16, and it makes the concern sharper.** Both
scanners now measure almost exactly the predicted budget: 1,420,664 obj/s at
1,387 MB/s is 977 B per object, reading nothing but the inode table, at 99% of
the device. There is no headroom left to absorb a seek per object — the cold
rate *is* `metadata read bandwidth ÷ bytes per object`, demonstrated across a
7× range of rates and two independent implementations. So an xattr-regexp filter
does not cost the target some percentage; it changes the divisor. Any filter
needing a non-inline xattr has to be priced as a separate scan mode, not as a
predicate.

**Sharpened 2026-08-16 — [`filter-levels.md`](filter-levels.md) §§3, 6, 7.**
"Needs a non-inline xattr" is not a property of the predicate. `mkfs.lustre`
sizes MDT inodes precisely so LMA, LOV, SOM and linkea fit *inside* them
(`libmount_utils_ldiskfs.c:860-890`), so `--pool`, `--stripe-count`, `--name`
and `--size` are all inline on a normally-provisioned MDT and all external on a
wide-striped one (>59 stripes → 512 B inodes, layouts always external, bz
7241). What needs measuring is the **spill rate per filesystem shape**, not a
per-predicate verdict.

Two things follow. **It is already instrumented** — the device scanner reports a
tier-2 rate, and the OSD scanner gets it free by counting `osd_iit_iget_raw()`'s
`-EAGAIN` fallback. What exists is 0.0% of 12M inodes on the lab ldiskfs MDT and
1 spill in 1351 objects on the real ZFS MDT: both default-striped, so a lower
bound only. **And it is backend-shaped** — on ZFS every Lustre xattr arrives in
one `SA_ZPL_DXATTR` unpack that profiled at 0.0%, so there is essentially no
cliff there. Any claim that a filter misses the target needs a backend attached
to it.

### Filter predicate classification

The operator set is now given across both documents — `find`/`lfs find`-equivalent
attribute filters, plus `in list`, `range` (min-max), `largest`, `smallest`,
`min (+list)`, `max (+list)`, `count`, `sum`, `histogram`. Filterable dimensions
per LUG slide 20: attributes (ranges), IDs (range, list), **xattrs (regexp)**,
MDT/OST (range, list), pool. Advanced operators should be supported by the
protocol even where not initially implemented for all attributes.

Still needed: walk every `find_param` field through `cb_find_init()`
(`liblustreapi_pfind.c:2413`) and classify each as inline-attribute (cheap),
xattr-requiring (see *Does the target survive real filters*), or userspace-only.

**Done 2026-08-16 — [`filter-levels.md`](filter-levels.md).** All 34 `lfs find`
predicates enumerated and assigned a tier, for the OSD scanner and both
device-scanner backends, using the existing §6 tier model
(`design-ldiskfs-scanner.md`) rather than a second vocabulary. Five findings
change the design rather than just recording it:

- **`--size`/`--blocks` are tier 1, not tier 0.** An MDT inode's `i_size` is not
  the file's size for a striped regular file, and its `i_blocks` counts the MDT
  inode's own blocks; the number to read is `trusted.som`. An MDT-only scan
  therefore implements `lfs find --lazy` semantics exactly — and SOM is written
  on close, so a size filter has a third outcome, *unknown*.
- **The §6 tier table has two errors**: `size, blocks` at tier 0, and SOM at
  tier 2 when `mkfs.lustre` budgets it inline.
- **The LUG slide-21 example is not all-tier-0**, because of `-blocks +1G`.
  Predicted from `mdt_handler.c`, not yet reproduced on a real MDT.
- **No predicate is inherently tier 2.** Every tier-1 predicate *becomes* tier 2
  when its xattr spills — data-dependent, not query-dependent. See the sharpened
  note under *Does the target survive real filters* above.
- **Free predicates unimplemented on every scanner**: `--btime`/`--projid`/
  `--attrs` need `la_btime`/`la_projid`/`la_flags`, absent from the ldiskfs
  `DOIF_ATTR` and block-parse paths though the **ZFS OSD path already has all
  three**; and both device backends parse only `trusted.lma`, so no layout,
  pool, name or size predicate is implementable there at all — 3 of 34
  predicates exist today.

**Implemented 2026-08-17 for both device backends —
[`filter-levels.md`](filter-levels.md) §5.2.** `src/lfu_filter.{c,h}` compiles
the `lfs find` vocabulary into a predicate array plus a **demand mask**, so a
pure tier-0 query never opens the xattr area and a tier-1 query reads exactly
the xattrs it needs. 33 of the 34 predicates now work on both device backends
(the tier-3 depth pair excepted); the in-kernel OSD scanner is untouched and
still has the three tier-0 gaps. Three things the implementation forced:

- **`--blocks` now means the file's blocks, via SOM**, and the old
  inode-allocation test is `--dev-blocks`. That answers *Which `--blocks` LFU
  means* for two of its three candidates; OST-actual still needs an OST scan.
- **A backend refuses what it cannot answer** rather than returning "no
  matches" — `lfu_target_ops.can_supply`, `.attr_mask`, `.missing_fields`. This
  is the attribute-mask definition this item was blocking on, arrived at from
  the bottom: the mask is a property of the *target*, not of the protocol.
- **Design question M9 is answered** (`ext2fs_xattrs_read_inode()` does follow
  `i_file_acl`), which makes tier 1 free and correct on ldiskfs but makes the
  tier-2 *cost* unmeasurable from outside libext2fs.

**Extended to the OSD scanner the same day —
[`filter-levels.md`](filter-levels.md) §5.4.** The evaluator is now one source
built into both the userspace scanners and the `lfu_ring` kernel module, where
it runs between `rec()` and the ring (design-osd-scanner.md §4's pushdown); the
three tier-0 fields are filled on both OSD read paths, and tier 1 is served by
a `rec(DORA_XATTR)` iterator extension out of the mapped inode-table block. The
"filter program is UAPI" requirement is met by `struct lfu_filter` as an ioctl
payload, validated index by index before use. **Built and run 2026-08-17 on a GCP lab** —
[`filter-pushdown-measured-2026-08-17.md`](measurements/filter-pushdown-measured-2026-08-17.md):
every predicate agrees with the userspace device scanner on the same device, the
`-blocks +1G` trap is reproduced on a real MDT, tier 2 fired once out of 302,122
objects and was counted, and a rejecting tier-0 filter runs **8% faster than no
filter at all** because a rejected object never enters the ring. Cold, parallel
enumeration into one ring, and ZFS remain unmeasured. **osd-zfs gained the same
`rec(DORA_XATTR)` later that day, and it too is now built and run** — served
from the SA xattr nvlist its iterator already unpacks for the LMA
([`zfs-tier1-measured-2026-08-17.md`](measurements/zfs-tier1-measured-2026-08-17.md)): the
whole vocabulary works on a live ZFS MDT, 14 of 14 filters agree with the
userspace scanner, and tier 1 costs 1.6% there against 27% on ldiskfs. Cold and
parallel enumeration into one ring remain unmeasured on both backends.

**Still blocks:** the protocol-level filter/aggregation encoding — the operators
in the LUG list that are not selections (`largest`, `histogram`, `count`, `sum`)
are unimplemented, and `filter-levels.md` §9's sharding constraint applies to
them. Also unresolved: what an *unknown* size means to an aggregation.

### Does readahead cost anything warm? **[new 2026-08-17]**

Unmeasured, and it bears on a published headline. Every row of the warm curve in
[`blockparse-2026-08-16.md`](measurements/blockparse-2026-08-16.md) §3 — including the
17,392,147 obj/s peak and the 10.4× — ran at `lfu_ra_blocks=32`, the default,
and the axis was never swept warm.

Warm, readahead cannot help: every inode-table block is a page-cache hit, so
each `sb_breadahead()` is a buffer-cache lookup that accomplishes nothing while
taking the same lock as the `sb_bread()` it precedes — on a path where spin is
still 36.62% of the profile. Roughly two lookups per block where one would do.
So the warm peak is plausibly a floor.

The root cause of the omission is worth fixing regardless: `lfu_par`'s report
line records `dev`, `private`, `nthreads`, `chunk` and `recattr` but none of the
three `osd_ldiskfs` tunables (`lfu_blockparse`, `lfu_ra_blocks`,
`lfu_noverify`) the run actually depended on, so every published `bp=` was a
hand-written label — a label that can be wrong, and an axis that can go
unrecorded. [`tests/bench_osd_sweep.sh`](../tests/bench_osd_sweep.sh) closes it
from the harness side by deriving every label from a sysfs readback; the cleaner
fix would be for `lfu_par` to print them itself, which needs a way for one
module to read another's parameters.

**Answered 2026-08-17 — it costs, by 22% at one thread and 90% at four**:
[`warm-readahead-and-cold-2026-08-17.md`](measurements/warm-readahead-and-cold-2026-08-17.md).
`ra=0` gives 5.21M obj/s at j1 against 4.26M at the default 32, and 15.1M against
7.95M at j4, monotonic across the window range, with the iget-path control moving
only ~7% as predicted. So the published warm rows were understated, and by more
at higher thread counts.

**The follow-on is now the live question, and it is sized.** `lfu_ra_blocks=32`
is wrong in two of three regimes: it costs up to 90% warm, is irrelevant when
the device is bandwidth-saturated (measured: cold flat within 0.9% across every
window, because the scan sits at ~100% of a 183 MB/s disk), and is worth 8× only
cold *and* latency-bound (the 2026-08-16 NVMe result). The window wants to be
adaptive on whether `sb_bread()` is hitting the buffer cache. That is a design
change, not a tuning change.

### Does filter pushdown cost anything? **[answered 2026-08-17]**

No — it is free or better in every regime measured
([`warm-readahead-and-cold-2026-08-17.md`](measurements/warm-readahead-and-cold-2026-08-17.md)
§3). Warm, a rejecting tier-0 filter is **+8%** because the object never enters
the ring; cold it is +4%. And **cold, a tier-1 predicate costs nothing at all**:
`--name` did 302,018 xattr lookups at the same rate as no filter, because the
xattr is in an inode-table block the scan was already paying for. Tier 1 is a CPU
cost, visible when the scan is CPU-bound and invisible when it is device-bound —
which is the tier model seen from the other side.

### Kernel-side Object Stream encoding **[new]**

Deferred rather than avoided. The initial ldiskfs scanner runs in userspace, so
FlatBuffers encoding happens where the library exists. But the OSD API Input
Scanner exports through `circ_buf` from *kernel* context, and neither FlatBuffers
nor MessagePack has a kernel-space encoder in-tree or upstream (`grep -rli` over
`lustre-release` returns zero hits for both).

The HLD also notes the OSD path "might require at least basic attribute filtering
to be implemented in the kernel" — so kernel-side filter evaluation lands
alongside kernel-side encoding.

The format gets frozen in step 1 of the build order; the kernel encoder isn't
needed until step 6. **The question must be answered before the format is frozen,
not when the encoder is needed.**

### Slow-consumer policy on a shared fan-out buffer **[new, 2026-08-06]**

Dilger, reviewing the fan-out design: with the OSD API scanner there should be
only one scan running at a time, and it should **share the memory buffers**
between consumers rather than forking a copy of the stream per consumer — so
that N filters/consumers do not multiply the device IO.

That is right, and it supersedes the "per-consumer ring" row copied from
`ofd_access_log.c` (see `design-osd-scanner.md` §5.1). But it collides with the
other divergence already specified there — *stall the producer, never drop
silently*. With one shared buffer, reclaim is gated by the **slowest** consumer,
so "stall" means one slow or hung consumer stalls the scan for every other
consumer.

The two candidate policies:

1. **Stall on slowest.** Correct and simple; a hung consumer becomes a hung
   scan unless paired with a timeout that *evicts* the consumer rather than
   blocking behind it forever.
2. **Advance past a lagging consumer** and hand it an `LFU_REC_GAP` marker, so
   it learns its view is incomplete while the others proceed at full rate.

Likely answer is (2) with (1) as the default for consumers that declare
themselves completeness-critical (a migrate or delete consumer must not be
handed a gap silently) — but this needs deciding before the transport is built.
The invariant that must not bend either way: **a consumer is always told when
its view is incomplete.**

Note the IO-amplification argument is transport-level and applies to the
**Option 1 userspace scanner too**, where nothing prevents N concurrent scans —
it is simply wasteful to run them. So consumer fan-out is mandatory in v1 for
two independent reasons: the OSD iterator singleton (*Iterator singleton*, resolved) *and* device
IO amplification, which holds even where there is no singleton.

### Access control granularity

The Server Bulk RPC Filter Rule Module must enforce POSIX UID/GID/ACL, filesets
and nodemaps server-side before returning entries.

Project-based filtering is checkable straight from the inode. Per-user POSIX
checking needs the parent directory, hence a linkea walk — so the cheap subset is
reachable early and the expensive subset is gated on path resolution (*Path resolution priced separately*). Worth
confirming project-scoped filtering satisfies the first pass.

Substantial nodemap/RBAC/fileset infrastructure is landing in 2.17–2.18 and
should be built on rather than reinvented: LU-19975 (RBAC on default nodemap),
LU-19884 / LU-19963 (`foreign_dir`, `lqa`, `projid` ops in nodemap RBAC),
LU-18357 (multiple read-only filesets per nodemap), LU-18109 (nodemap ID offset
ranges).

Referenced but not yet read: **LU-16524** (Buisson, "Limit capabilities of local
admin").

### LFSCK and OI Scrub coordination

**Largely answered 2026-08-15/16 by measurement.** They do not have to serialise:
a `DOIF_PARALLEL` private iterator ran the full namespace *while* a verifying OI
scrub was scanning — 1,476,086 obj/s on ldiskfs, 392,560 on ZFS — and the scrub
finished `updated: 0, failed: 0`. The control that makes it evidence is that the
singleton path returns `-114` on the same build. Block parsing does not change
this: the scrub path still goes through `ldiskfs_iget()` and still repairs OI
mappings; only the private path parses raw
(`parallel-osd-measured-2026-08-15.md` §5, `blockparse-2026-08-16.md` §1).

Still unanswered operationally — whose checkpoint state, and who arbitrates disk
bandwidth. The second is sharper than it was: the private path now saturates the
device cold, so "LFU and LFSCK coexist" means they compete for the same NVMe
queue rather than for the same iterator.

Sharper given the "one scan, N consumers" requirement: if LFU multiplexes one
scan across consumers, it needs a fan-out layer, and LFSCK is just another
consumer.

### Restart, checkpoint and scan identity

Not covered by either document. Resumable scans? Cursor stability across MDT
failover? What happens to a consumer that disconnects mid-scan?

The Raw Write / Raw Read module pair gives a partial answer for replay, but not
for resumption. The lab cluster's MDS failover setup makes this directly testable.

## Reference gaps

- **LU-16742** (LMR-FID, "Dir entries with multiple FIDs") and **LU-17820**
  (LMR2) — needed to assess *LMR duplicate objects*.
- **WBC2** flush-policy detail — needed to assess *WBC invisible metadata*. `osd-wbcfs` is in the
  v2.17 tree and is the nearest available reference.
- **LU-17814** — "`lfs find` to scan with multiple threads"; the HLD says to
  extract the Lustre Namespace Input Scanner from it. This is
  `liblustreapi_pfind.c` in tree. Read the ticket for design intent.
- **LU-16524** — local admin capability limits; relevant to *Access control granularity*.
- **Lester** — `github.com/ORNL-TechInt/lester`, and `e2scan` in the WhamCloud
  e2fsprogs tree. Both are direct precedents for the initial scanner and worth
  reading before writing it.
- **zester** — `github.com/iu-hpfs/zester` (raised by Timothy Day, 2026-08-06).
  ZFS/Lustre metadata reconstruction by parsing `zdb -dddd` output; Python 2,
  Lustre 2.8 / ZFS 0.6.5 era, regular files only, no DNE, known to over-report
  sizes. **Read for its MDT↔OST join logic and size-reconstruction pitfalls,
  not as an implementation base** — see `architecture.md` §6c for why ZFS
  coverage goes through the OSD API scanner instead.

## Tracking

TLU-186 (TLC, In Progress) · LU-20462 (WhamCloud epic, Open, Artem Blagodarenko).
HLD authored by Andreas Dilger.

Filed from this work: **LU-20602** — MDT-internal objects carry no LMA flag
marking them internal (2026-08-18; source text and open items in
`tickets/lma-internal-objects.md`).
