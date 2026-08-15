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

**Blocks:** filter module design, attribute mask definition.

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

Partly answered: the OSD API scanner reuses the OI Scrub scanner, and LFSCK may
become an Object Stream consumer. Unanswered operationally — can an LFU scan and
an LFSCK run share the iterator or must they serialise? Whose checkpoint state?
Who arbitrates disk bandwidth?

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
