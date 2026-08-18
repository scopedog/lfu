# Andreas's Comments, 2026-08-18: What They Change and What To Do

**Source:** [`andreas-comments-2026-08-18.txt`](andreas-comments-2026-08-18.txt) —
twelve paragraphs of review on the LFU design, sent by mail because "I couldn't
find any way to comment on your docs".

Sorted by what each comment *does* to this repository rather than by the order
he wrote them. Three overturn a decision recorded here, five are code or
measurement this project is already equipped for, one is a ticket he asked for
directly, three are closures, and two open new design work.

Nothing below is done yet. This is the work list.

---

## A. Decisions of ours he reversed — the repo is wrong until these are fixed

### A1. Record format: MsgPack is out, Cap'n Proto is in the running

> "previous analysis showed FlatBuffers is superior to MsgPack due to the ability
> to integrate with RDMA zero copy (see my previous comments on TLU-219). Another
> prominent contender is Cap'n Proto that Tim suggested. It has a C
> implementation and could be ported to the kernel and integrate with LNet bulk
> RDMA transport."

**Wrong here now:** [`open-questions.md`](open-questions.md) §*Object Stream
format: FlatBuffers preferred* (in **Resolved**, names MessagePack a contender),
[`README.md`](../README.md) "FlatBuffers or MsgPack",
[`architecture.md`](architecture.md) §2 and §4.

**Change:** MsgPack out. Contenders are FlatBuffers and Cap'n Proto, and the
selection criterion is **zero-copy access + LNet bulk RDMA integration + kernel
portability**, not encoded size or schema ergonomics.

**This answers our own blocking question.**
[`open-questions.md`](open-questions.md) §*Kernel-side Object Stream encoding*
says neither candidate has a kernel-space encoder and that the question "must be
answered before the format is frozen". Cap'n Proto's C implementation is the
proposed way out, and evaluating it is now on the critical path.

**What we can contribute rather than just adopt.** `struct lfu_wire_rec`
([`src/kernel/lfu_ring.h`](../src/kernel/lfu_ring.h)) is already a fixed-layout,
168-byte, `_Static_assert`ed, version-gated record that the consumer validates
through `LFU_RING_IOC_INFO` before trusting a byte. That is already zero-copy
and already the shape LNet bulk wants. So the open question is *schema evolution
and cross-language access*, not encode throughput — and the number that needs
bounding is what any encoder costs at the 3.5M obj/s the ring currently
sustains.

- [ ] Evaluate `capnp-c` and `flatcc` for kernel portability: no floating point,
      no `malloc`, bounded stack, licence compatibility.
- [ ] Bound the per-record encode cost against the measured no-filter rate.
- [ ] **Blocked:** ask Andreas for the TLU-219 analysis. That is Whamcloud's
      tracker and is not readable from here.

### A2. Merge location: reopened

> "Merge Filter - I think this is generic enough that it should have both a
> kernel and userspace implementation. It isn't clear whether merging multiple
> MDT/OST streams on the server is a net win vs. having two open streams, and has
> drawbacks if the target migrates to another server during the scan."

**Wrong here now:** [`open-questions.md`](open-questions.md) §*Merge location*
is filed under **Resolved** — "LUG slide 21 pins it down: a Split/Merge Server
PtlRPC Bulk module sits on the server" — and
[`architecture.md`](architecture.md) §1 repeats it as "Merge is server-side in
the target deployment."

**Change:** move §*Merge location* back to **Live questions**, record his
migration argument (restarting an independent target scan elsewhere is easy;
locally merged streams that now depend on a remote server are "very messy"), and
require **both** a kernel and a userspace implementation rather than treating
userspace merge as a staging artefact.

**Knock-on:** [`open-questions.md`](open-questions.md) §*LMR mirrors inodes
across MDTs* and [`architecture.md`](architecture.md) §9 both place FID dedup
"in the Split/Merge module". If merge can legitimately be client-side, dedup has
to be available there too, so it cannot be specified as a server-only property.

### A3. Pathnames belong in the Object Stream

> "For device/OSD scanners, Lustre provides the trusted.link xattr to give the
> parent FID+filename for each object, and if pathnames are at all interesting to
> the consumer then this should be returned, since it allows userspace to
> generate pathnames efficiently in bulk by reconstructing directory trees
> incrementally and then reconnecting them to the filesystem ROOT/ or mountpoint."

**Wrong here now:** [`architecture.md`](architecture.md) §1 — "**Only FIDs cross
the wire**; pathnames are attached at the very last stage" — and
[`open-questions.md`](open-questions.md) §*Path resolution is an Output Format
module, priced separately*.

**Change:** path resolution stays an Output Format module and stays excluded
from the rate target, but its *inputs* now ride in the stream. He also flags the
access-control interaction we already noted independently: a subdirectory or
nodemap-restricted scan may force the MDS to walk inode→mountpoint anyway to
validate access, in which case it may as well return the pathname.

He explicitly leaves ship-vs-regenerate open — "having the ability to provide it
in the object stream allows this decision to be deferred/tuned later" — which is
B2 below.

---

## B. Code and measurement this project can do

### B1. Wire v3: parent FID + name from linkea

The kernel already decodes linkea. `lfu_linkea_name()`
([`src/lfu_filter_eval.c`](../src/lfu_filter_eval.c)) walks it to answer
`--name`, including the two byte-order rules — host-order header identified by
magic, big-endian unaligned `lee_reclen` — that `53cbbe6` corrected and that the
lab then proved on a linkea the MDT wrote. What it does not do is *emit*
anything: `struct lfu_wire_rec` carries no parent FID and no name.

- [ ] Wire version 3: parent FID (16 B) plus a bounded name, gated by a demand
      bit so a query that does not want them does not pay.
- [ ] Bump `LFU_RING_WIRE_VERSION`; the append-only rule and the `INFO`
      handshake already make this safe for an old consumer.

### B2. Then measure ship-vs-regenerate — he asked for exactly this

> "We should question/investigate whether shipping the full pathname (up to
> 4KiB+ per object) is more costly than regenerating it on the client."

This project is in an unusually good position to answer it, because the ring
cost is already measured rather than assumed:
[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md)
§6 shows a rejecting filter running **8.3% faster than no filter at all**, with
`--type f` as the matches-everything control at −0.4% and `stalls=0` throughout —
so the +8% is the emit path and nothing else. The emit path is therefore the
scarce resource, and a 4 KiB pathname is a ~25× inflation of a 168-byte record.

The prediction is that full pathnames are the wrong default and bounded
parent-FID+name is right. It is a prediction until measured.

- [ ] Rate with parent FID + name vs wire v2, warm and cold.
- [ ] Rate with a full pathname field, same conditions.
- [ ] Cost of reconstructing trees in bulk in userspace from parent FIDs, for
      the other side of the comparison.

### B3. An xattr-name predicate

> "The xattr regexp is primarily going to be on the xattr name so this is
> typically stored in the inode even if the value is external."

Directly implementable. `osd_raw_xattr()`
([`patches/otable-xattr-v2_17_55.patch`](../patches/otable-xattr-v2_17_55.patch))
already walks the in-inode xattr entry list looking for one name; exposing the
*list* of names is a small extension of the same walk. That makes an xattr-name
predicate tier 1 at close to zero cost, which is his claim, testable.

The filter has no such predicate today — `LFU_F_*`
([`src/lfu_filter.h`](../src/lfu_filter.h)) ends at `LFU_F_NAME`.

- [ ] Extend the raw xattr path to enumerate names.
- [ ] Add the predicate to the shared evaluator, both builds.
- [ ] Measure it against the tier-1 rows already in the table.

### B4. `LFU_REC_GAP`: accepted, and refined into a resume protocol

> "Each consumer should track which object it last processed, and when if it gets
> LFU_REC_GAP when it rejoined it would get the current minimum available object,
> and have to re-scan the objects in the gap after the rest of the scan completes
> (or restart the scan there if it had completed)"

He accepts the marker — [`open-questions.md`](open-questions.md)
§*Slow-consumer policy on a shared fan-out buffer* option (2), and
[`design-osd-scanner.md`](design-osd-scanner.md) §5 — and adds the recovery
semantics we left unspecified.

This is real code, not a doc edit: [`src/kernel/lfu_ring.h`](../src/kernel/lfu_ring.h)
states **one reader at a time**. A per-consumer cursor and a gap range mean
building the multi-consumer fan-out this project has so far deferred.

- [ ] Write the resume protocol into `design-osd-scanner.md` and `open-questions.md`.
- [ ] Per-consumer cursor + gap range in the ring.
- [ ] Test: a deliberately slow consumer gets a gap, re-scans it, and ends with
      the same FID set as a consumer that never lagged.

### B5. Merge, both sides, and measured

Follows from A2. The userspace merge with FID dedup is needed for LMR anyway, so
build it and settle his "not clear whether it is a net win" with a number.

- [ ] Userspace merge + FID dedup.
- [ ] Merged stream vs two open streams, same workload.

---

## C. The ticket he asked for

### C1. LMA on internal objects

> "it would be worthwhile/useful to file a ticket and fix the code to set an LMA
> to mark them as internal objects. This can be checked/set when the objects are
> opened/checked in the 'initial LFSCK' so that the scanners handle this properly
> as they upgrade"

We measured this and have the table:
[`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) §5 records
`/CONFIGS/mountdata` as `[0xe:0x0:0x0]` (IGIF, seq = its own inode number) and
both `/update_log_dir/*` objects on normal sequences, all three with
`compat=0 incompat=0` and therefore indistinguishable from user objects by LMA
alone. [`option-comparison.md`](option-comparison.md) and
[`design-osd-scanner.md`](design-osd-scanner.md) §1 both carry it as the reason
Option 1 needs a hand-maintained denylist.

- [x] **Filed 2026-08-18 as LU-20602**, with that table as the evidence; source
      text and remaining open items in
      [`tickets/lma-internal-objects.md`](tickets/lma-internal-objects.md).
      The fix turned out to be one flag argument in the initial OI Scrub
      (`osd_scrub.c:1918`), on a **new** `LMAC_INTERNAL` compat flag —
      `LMAC_NOT_IN_OI` gates the OI insert these objects need.
- [ ] Note in the ticket that existing filesystems still need the denylist
      through the upgrade window, so the scanner-side workaround does not go
      away when the fix lands.

---

## D. Closures — his answers, to be recorded

### D1. LMR: our highest-priority open question, answered in principle

> "Since LMR is only at the architecture stage, we can implement it with whatever
> benefits LFU. Storing a 'primary vs. replica' marker in the MDT objects is
> reasonable, and/or it could be determined by the MDT FID SEQ rage returned. The
> consumer (or merge filter) would have to know if an MDT is offline to decide
> whether the replica object should be used, or the object iterator could
> transparently mask this flag/FID to the primary if the target is offline.
> LU-17818 and linked tickets have some docs and discussion about LMR."

[`open-questions.md`](open-questions.md) §*LMR mirrors inodes across MDTs* is
marked **[new, highest]** and "blocks record layout, merge module semantics,
correctness of every aggregate". It is now answerable: LMR is early enough that
LFU can ask for what it needs.

- [ ] Read LU-17818 and linked tickets (add to §*Reference gaps*, which
      currently lists LU-16742 and LU-17820 for this).
- [ ] Rewrite the section as *resolved in principle, with a concrete ask*: a
      primary/replica marker, or FID SEQ range inference, plus iterator-side
      masking when a target is offline.
- [ ] Say where the marker rides. The record already carries `wr_lma_compat`,
      `wr_lma_incompat` and an `wr_lfu` flag word, so LMA is the natural home
      and the wire record needs no new field beyond a bit.

### D2. WBC: not a roadblock

> "the inconsistency here is largely 'Schrödinger's Cat', so WBC collapses
> (incrementally) to regular directories/files when viewed, and will be within
> the 5-30 seconds of normal caches by necessity... if an 'uptodate' scan is
> needed then WBC could be force-flushed before the scan started, but could
> immediately be outdated again."

- [ ] Move [`open-questions.md`](open-questions.md) §*WBC holds metadata no
      device scan can see* to **Resolved**, with the force-flush note and the
      ldiskfs-vs-dcache analogy he draws.

### D3. Lazy size on the MDT: the upstream fix direction

> "File LSOM updates to store proper size via FLR for regular stat() usage would
> allow non-FLR files to store a strict size in SOM to make scanning efficient.
> Files that are not closed for a long time could periodically write the
> trusted.lsom xattr (or send size+blocks to MDT) to update size."

[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md)
§3 measured SOM reporting `blocks=3129344` against the client's glimpsed
`3145728` — 0.5%, lazy SOM being lazy — and insisted an MDT-only size answer be
labelled as such. That stance holds; his note is the path by which it stops
being necessary.

- [ ] Record the direction in `filter-levels.md` §4 alongside the existing
      lazy-SOM caveat.

---

## E. New design work he opened

### E1. Index discovery, and index-vs-scan

> "How does a query decide whether using an index is faster than a scan...? How
> does a query even know which indexes are available? We should be able to use an
> index as a starting point to drive an object scan and further filtering."

Three protocol questions, and he is explicit that indexes are "an implementation
extension, but should be considered during protocol design" — so they cannot be
deferred wholesale the way [`open-questions.md`](open-questions.md) §*Index
priority* currently leans.

There is a precedent to build on in this repo: `LFU_RING_IOC_INFO` is already a
capability handshake — wire version, record size, which xattrs this OSD can
serve, which `--attrs` bits its flag word carries — that a consumer checks
before it trusts a record. Index discovery is the same shape.

- [ ] Specify index discovery as a capability query.
- [ ] Specify *index as a scan starting point*: index → FID set → object scan →
      further filtering, which is also how a projid index would drive a
      subdirectory scan.
- [ ] Fold in the largest/newest-file index sketch already in
      [`architecture.md`](architecture.md) §6.

### E2. OST-side size semantics

> "the MDT can get this from SOM xattr, while OST could estimate the file size
> from object size * trusted.fid::ff_layout.ol_stripe_count. However, in many
> cases OST scans care more about the size of the object and not the file because
> they are space management operations trying to reduce usage on that specific
> OST."

The second sentence matters more than the first.
[`filter-levels.md`](filter-levels.md) §4 and
[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md)
§3 pinned `--size` / `--blocks` / `--dev-blocks` on the **MDT** and never
specified the OST side. That is a real gap, and the default there is probably
the object's own size rather than the file's.

- [ ] Specify OST-side size semantics in `filter-levels.md`.
- [ ] Record the `ff_layout.ol_stripe_count` estimate as available but not the
      default.

### E3. PCC-RO / TCU / ECRO as LFU tools in 2.18

> "that would be desirable, and possibly achievable... AFAIK there is an initial
> TCU scanner based on lfs pfind in patch 'LU-19598 utils: implement ltrash_purge
> tool', but it is still incomplete. I think that scanning is only part of the
> work needed for the PCC/TCU tools to be production ready, they also need
> incremental updates and internal histogram to track oldest objects without
> keeping billions of objects in memory in a sorted list."

He agrees with [`architecture.md`](architecture.md) §9c and
[`open-questions.md`](open-questions.md) §*Named consumers ship a release before
LFU* — the window closes when 2.18 ships — and adds a requirement we did not
have. The bounded histogram is an **aggregate Filter Rule**, so it folds into
E1 rather than being a per-tool concern.

- [ ] Read the LU-19598 `ltrash_purge` patch; assess whether `lfind`'s Output
      Format can back it.
- [ ] Add "incremental updates + bounded histogram" to the consumer
      requirements, and note the histogram as an aggregate.

---

## F. Housekeeping

- **He could not comment on the docs.** Enable Issues or Discussions on
  `scopedog/lfu`, or point him at the published pages, which carry comment
  threads. Cheap, and it is the reason this feedback arrived as twelve
  paragraphs of mail.
- **"Hopefully Jinshan will join the LFU effort rather than duplicating it."**
  The measured comparison already exists —
  [`xiong-68020-filter-measured-2026-08-17.md`](xiong-68020-filter-measured-2026-08-17.md):
  their 68020 filter selects on the MDT's zero size, is +26% for their baseline,
  and is 6–7× slower in absolute terms than the filter here. That is the useful
  thing to put in front of both of them.
- **The 1M obj/s target.** No action beyond replying with numbers: his reasoning
  ("all xattrs for most files live inside the inode, so can be filtered without
  an extra read while maintaining the scan rate") is the tier model this project
  built and measured — `inline=302018`, `external=1`, `iget=0` out of 302,122
  objects, tier 1 costing 12.8–26.6% warm and nothing at all cold. His
  1 GiB/s ÷ 1024 B/inode arithmetic matches the finding that cold is
  bandwidth-bound. He also mentions a Changelog of STALE FLR files as the way to
  avoid repeat full scans once the initial one is done — an ECRO input worth
  recording.

---

## Suggested order

1. ~~**C1**, the ticket~~ — **done, LU-20602.**
2. **A1–A3 and D1–D3** — the doc retractions and closures. The repository states
   two things that are now wrong (merge is server-side; only FIDs cross the
   wire) and one that is out of date (MsgPack).
3. **B1 + B2** — wire v3 and the ship-vs-regenerate measurement. The highest
   value item, because it answers a question he raised with the one kind of
   evidence this project reliably produces.
4. Everything else.
