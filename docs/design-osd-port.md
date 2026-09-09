# Porting the OSD scanner into Lustre, and putting `lfs find` on it

**Date:** 2026-09-09 · **Status:** design proposal, v0.1, nothing written
**Parent:** [`design-osd-scanner.md`](design-osd-scanner.md) — the scanner itself
**Sibling:** [`design-lfs-find-on-scan.md`](design-lfs-find-on-scan.md) — how find
was split so a second object source could exist
**Release:** in-kernel OSD work is 2.19; the userspace half it plugs into landed
for 2.18 (round 23, pushed 2026-09-09)

The scanner exists, is measured, and lives outside the tree. This is about
getting it *into* Lustre and reaching it from find's vocabulary. It is a
porting and sequencing problem far more than a design one — the hard technical
questions were answered in August, and the value of this document is in the
four decisions that are still open and the order the pieces land in.

---

## 1. What exists today

Nothing here needs inventing. The inventory, all of it built and most of it
measured:

| Piece | Where | State |
|---|---|---|
| `rec()` attribute extension | `patches/rec-attr-v2_17_55.patch` (+ `-zfs`) | built, run, both backends |
| Private parallel iterators | `patches/parallel-it-v2_17_55.patch` | ldiskfs **2.03M obj/s** (2.4×), ZFS **561k** (3.64×) |
| Block parsing (no `iget`) | `patches/itable-blockparse-v2_17_55.patch` | **17.4M warm**, **1,420,664 cold** = 0.99× the userspace device scanner |
| Inode-table readahead | `patches/itable-readahead-v2_17_55.patch` | the cold number above depends on it |
| `rec(DORA_XATTR)` for tier-1 | `patches/otable-xattr-v2_17_55.patch` | built; filter pushdown depends on it |
| Object Stream producer | `src/kernel/lfu_ring.c` (843 lines) | misc device, ring, kthread, in-kernel filter |
| Userspace consumer | `src/lfu_scan_kmdt.c` (442 lines) | the third backend, filter pushdown, `-j` forced to 1 |
| Filter evaluator | `src/lfu_filter_eval.c` | one file, compiled into **both** kernel and userspace |
| Measurement harnesses | `lfu_it.c`, `lfu_par.c`, `lfu_fanout.c` | **not** for porting — they answered questions and are done |

Seven patches touch five Lustre files: `dt_object.h`,
`osd-ldiskfs/{osd_scrub.c,osd_internal.h}`, `osd-zfs/{osd_scrub.c,osd_internal.h}`.

## 2. The seam — and it already fits

The structural finding that makes this cheap, and it was not planned:

`lfu_scan_kmdt.c` implements `open / close / worker_init / worker_fini /
scan_chunk`. The plugin interface that shipped in round 23 —
`struct llapi_scan_backend` in `lustre/utils/lustreapi_scan_backend.h` — is
`sb_open / sb_close / sb_worker_init / sb_worker_fini / sb_scan_chunk`. Same
five entry points, same shape, arrived at independently on the two sides.

So the kernel scanner does **not** need a new userspace API, a new `lfind` mode,
or any new user-facing concept. It becomes a third backend beside
`scan_osd_ldiskfs.so` and `scan_osd_zfs.so`:

```
  lfs find's predicates  (find_prefilter / find_want / find_decide)
              |
        llapi_find_device()            <- landed 2.18, unchanged
              |
        llapi_scan_device()            <- landed 2.18, unchanged
              |
     scan_backend_kind(device)         <- routes on the name
       |          |          |
   ldiskfs       zfs      **kernel**   <- the new one
   (offline)  (offline)   (LIVE target)
```

Everything above `llapi_scan_device()` — the predicate set, `lfind(8)`, the
record, `--fid2path`, `--paths`, the man pages — works with no change at all.
That is the whole argument for having done the userspace half first.

**What the new backend buys that neither existing one can:** the target stays
**in service**. ZFS refuses a live pool by design (`-EBUSY` on an `ACTIVE`
pool), and ldiskfs on a live device has the unvalidated torn-read exposure
(`open-questions.md`). The kernel scanner reads through the buffer cache from
inside the running server. That is not a speed argument — it is the only way to
scan a serving target at all.

---

## 3. The four decisions

### 3.1 The Jinshan collision — land the fast path first, decide the UAPI later

Jinshan Xiong's **LU-20591** (68018 / 68019 / 68020) builds a scanner on the
same `osd_otable_it` primitive: `OBD_IOC_SCRUB_ITER` + `llapi_obj_iterate()` +
`lctl iterate_objects`. Checked 2026-09-09: **all three still `NEW`**, 68019 and
68020 untouched since 2026-08-31 and 2026-08-14.

The earlier recommendation ([[lfu-upstream-collision]]) was to put `DOIF_ATTR`
*under* their `scrub_iterate_objects()` rather than ship a rival UAPI. **Six
weeks of no movement changes that**: building on a stalled series makes our
landing date theirs.

**Recommend instead: separate the OSD-layer work from the UAPI, and land the
OSD layer on its own.**

The iterator extensions — `DOIF_ATTR` through `rec()`'s existing `attr`
argument, `DOIF_PARALLEL`, block parsing, readahead, `DOIF_NOSCRUB` — are
`dt_it_ops` semantics, not user-visible interface. They make *any* consumer
faster, theirs included: their walk does `dt_locate()` + `dt_attr_get()` per
object, which is precisely what these remove. Landing them:

- is cooperative rather than rival — it speeds up their series, not just ours;
- settles the performance argument in-tree, where it is checkable;
- leaves the UAPI question open without blocking on it;
- and takes `DOIF_NOSCRUB` from them rather than re-deriving it, which is the
  right acknowledgement.

The cost is real and must be planned for: **Lustre reviewers do not take
infrastructure with no consumer.** So group A lands *with* group B behind it in
the same series, but as separate reviewable changes, and the conversation with
Andreas and Jinshan happens on group A before group B is written.

**Action before any code:** put the split to Andreas and Jinshan — "we have
measured iterator extensions that make both scanners faster; can they land
independently of whichever control interface wins?"

### 3.2 The wire record stays compact — it is not `llapi_scan_rec`

Tempting to emit `struct llapi_scan_rec` straight from the kernel and skip a
translation. **Measured against, on two grounds:**

| | size | at 1,420,664 obj/s |
|---|---|---|
| `struct lfu_wire_rec` | **168 B** | 239 MB/s |
| `struct llapi_scan_rec` | **504 B** | **716 MB/s** |

Three times the ring bandwidth and three times the copy, for a record whose
extra bulk is mostly a `struct statx` the kernel would be filling with fields
the scan does not have. And decisively: `llapi_scan_rec` contains **pointers**
(`lfsr_name`, `lfsr_lmv`, `lfsr_parent_fd`), which cannot cross the boundary.

**Recommend: keep `lfu_wire_rec` as the wire format; the userspace backend
translates.** `lfu_kmdt_rec()` already does exactly this and is the code to
port. The Object Stream is a *wire* format and `llapi_scan_rec` is an *API*
format; conflating them costs bandwidth and buys nothing.

The wire record is versioned (`ri_wire_version`, `ri_rec_size`) and the
consumer refuses a mismatch rather than misparsing it — that discipline is
already in `lfu_scan_kmdt.c:79` and must survive the port.

### 3.3 Filter pushdown ships in v1, tier 0 first

Without pushdown the ring carries every object. `lfind --size +1G` over four
billion objects means four billion records copied — 672 GB at 168 B — to find
perhaps a thousand. With tier-0 pushdown it carries the thousand.

That is not a tuning argument, it is the difference between the feature working
and not working at scale, so **pushdown is in v1**.

But `struct lfu_filter` is 11,280 bytes of fixed-layout UAPI, and committing it
whole on day one is a lot of surface. **Phase it:**

- **v1: tier 0 only** — predicates answerable from the attributes already in
  the iterator's record (mode, size, times, uid/gid/projid, nlink, flags). No
  extra I/O, no dependency on `otable-xattr`, and it covers most of what people
  actually run.
- **v2: tier 1** — predicates needing an xattr (layout, linkea, SOM), which is
  what `rec(DORA_XATTR)` exists for.

The evaluator is the same file in both worlds already, which is what makes the
kernel and userspace answers identical by construction rather than by testing.
The validation discipline (`lfu_filter_validate()`, magic/version/size-checked
and index-range-checked before anything is evaluated) is non-negotiable in
kernel context and ports unchanged.

### 3.4 `lfu.ko`, and the kernel owns the parallelism

**Module placement:** a separate `lfu.ko`, not code in `mdt.ko`. The scanner is
not MDT-specific (OSTs need it too), `dt_otable_features` is an obdclass/OSD
interface, and a site that does not want LFU should load nothing and carry no
extra attack surface in the MDS. The counter-argument — the eventual bulk-RPC
path does live in the MDT handler — is real but is a later phase and can be a
weak dependency.

**Parallelism:** the kernel owns it. `DOIF_PARALLEL` runs N enumerator kthreads
over N inode ranges; the userspace backend reads **one** stream and reports
`tt_chunks = 1`. This is not a guess — the prototype settled it, and
`lfu_scan_kmdt.c` forces `-j 1` with the reason recorded: *"parallelism belongs
behind the enumerator in the kernel."* Two threading layers over one stream
would contend for a ring that is not the bottleneck at 239 MB/s.

If the single reader ever does become the limit, the escape hatch is already
designed: one shared buffer with per-consumer cursors
(`design-osd-scanner.md` §5.1), not a ring per reader.

---

## 4. What "make `lfs find` work with it" means

Three different things, and they are worth separating because only one of them
is `lfs find` proper.

| | What runs | Where | Needs |
|---|---|---|---|
| **L1** | `lfind --local` / `--target` / `--device` on a **live** target | on the server | groups A + B + C |
| **L2** | `lfs find` on a server node, against a local target | on the server | L1, plus a `lfs find` spelling for "scan this target" |
| **L3** | `lfs find` on a **client**, offloaded to every MDT in parallel | on a client | L2, plus the RPC, the connect flag, and the merge |

**L1 is the deliverable of this port** and it is nearly free: section 2's seam
means the backend appears and `lfind` gains live targets with no new user-facing
concept. It is also the only level that is fully testable in our lab.

**L3 is what the HLD actually asks for** — *"it should be possible for `lfs
find` to export search requests directly to multiple servers in parallel rather
than scanning the namespace locally"* (p.13, Client Bulk RPC Filter Rule
Module), with `OBD_CONNECT2_FIND_UTILITY` negotiation. The transport largely
exists: `OBD_IDX_READ` (op 403, `tgt_obd_idx_read()`) already fills pages with
records and bulk-PUTs them, with a resumable cursor and an attribute mask, and
its existing sender drives `dt_index_read()` → the same `dt_it_ops` we extend.
What does not exist: the MDC-side client, the scan-request encoding, the connect
flag, and the cross-MDT merge.

**And one unanswered question gates L3**, which no HLD revision addresses:
**duplicate FIDs across merged streams under LMR**. That needs putting to
Andreas before L3 is scoped, not during.

**Recommendation: scope L1 now, L2 as a small follow-on, and treat L3 as a
separate project** with its own design. Doing L1 first is not a detour — L3's
server half *is* L1's scanner, reached by a different transport.

**This needs your decision**, because "make `lfs find` work with it" most
naturally reads as L3, and L3 is roughly the size of everything done so far.

---

## 5. The change series

Three groups, landing in order. Sizes are estimates from the existing patches.

**Group A — OSD iterator extensions** (no UAPI, ~1,500 lines across 5 files)

| | Change | From |
|---|---|---|
| A1 | `osd: return attributes from the otable iterator` — `DOIF_ATTR` via `rec()`'s `attr` | `rec-attr` (+ zfs) |
| A2 | `osd: private otable iterators for parallel enumeration` — `DOIF_PARALLEL` | `parallel-it` |
| A3 | `osd-ldiskfs: read the inode table without iget` — block parsing | `itable-blockparse` |
| A4 | `osd-ldiskfs: readahead for the block-parse path` | `itable-readahead` |
| A5 | `osd: return xattrs from the otable iterator` — `DORA_XATTR` (v2, tier 1) | `otable-xattr` |

`DOIF_NOSCRUB` is adopted from LU-20591 rather than re-derived; if their series
has not landed by then, carry it with attribution.

**Group B — the Object Stream** (~1,000 lines, new module)

| | Change |
|---|---|
| B1 | `lfu: an object stream from the OSD otable iterator` — `lfu.ko`, ring, control device, kthreads |
| B2 | `lfu: evaluate the filter in kernel` — the shared evaluator, tier 0 |
| B3 | `lfu: tier-1 filter pushdown` — depends on A5 |

**Group C — userspace and find** (~500 lines)

| | Change |
|---|---|
| C1 | `llapi: a scan backend for a live target` — `scan_osd_kernel.so`, from `lfu_scan_kmdt.c` |
| C2 | `llapi: route a live target to the kernel backend` — `scan_backend_kind()` and the `-EBUSY`/in-service diagnostics |
| C3 | `utils: lfind on a mounted target` — man page, `--local` on a live target |

C2 is where the routing rule wants care: today an absolute path goes to ldiskfs
(round 23) and everything else reads as a ZFS dataset. A live target has to be
recognised *before* either, and the diagnostic when the module is not loaded has
to say so rather than "no backend".

---

## 6. Testing

The oracle is established and should not change: **the scanner's FID set
against `lfs find` + `lfs path2fid`**, which found 0 misses for the userspace
scanner and is the primary test.

| Test | Method |
|---|---|
| **Differential, offline** | OSD scanner vs `llapi_scan_device()` on the same **quiescent** target — identical FID sets and attributes. Neither has this oracle alone, and it is the strongest test in the set |
| Completeness | FID set vs `lfs find` on the mounted filesystem |
| **Live-load consistency** | The headline claim: the userspace scanner saw ~50% inconsistent inodes under create-heavy load; this should show **zero** |
| Internal objects | `/CONFIGS/*`, `/update_log_dir/*`, OI and quota files absent — the userspace scanner leaks three of these, this should leak none |
| LFSCK coexistence | Scan concurrent with a verifying OI scrub; both complete, scrub reports `updated: 0, failed: 0` (already demonstrated once at 1.41M obj/s) |
| Filter parity | Same predicate pushed down vs applied in userspace — identical sets. Cheap, because it is the same evaluator |
| Ring backpressure | Slow consumer; **no silent loss** — producer stalls or `LFU_REC_GAP` is set |
| **Foreground impact** | MDS metadata latency and cache hit rates under client load *during* a scan |
| Backend parity | ldiskfs and ZFS |

Two of these are load-bearing and neither exists yet: **live-load consistency**
is the claim that justified choosing this design over the userspace scanner, and
**foreground impact** is the top remaining risk. Nothing should ship on
throughput numbers.

---

## 7. Risks and open questions

| | |
|---|---|
| **Foreground impact** | Unmeasured. A scan inside the server consumes its CPU and cache. This is the top risk and no throughput number speaks to it |
| **Freshness after block parsing** | Block parsing reads inode-table *blocks*, not the live `struct inode`. Fresher than disk, but the mid-creation window is not provably closed the way the iget path closed it (`design-osd-scanner.md` §1.1, qualified) |
| **Inode checksum** | The raw parse does not verify it, so it *reports* a corrupt inode where `ldiskfs_iget()` refuses one. Defensible, but it belongs in the API contract |
| **Upstream API acceptance** | Is extending `rec()`'s `attr` acceptable, or will upstream want a new index feature? This is the one that can force a redesign |
| **Cost to existing users** | Can attribute capture happen without slowing OI Scrub and LFSCK, which share the path? *Answerable by reading code now, and should be settled before A1 is written* |
| **LMR duplicate FIDs** | Unaddressed in every HLD revision. Gates L3, not L1 |
| **WBCFS** | In scope or not? It already provides `do_attr_get` on the otable object |

---

## 8. What to do first

1. **Settle "cost to existing users" by reading code** — it is the cheapest
   open question and it gates the shape of A1.
2. **Put the group-A split to Andreas and Jinshan** — iterator extensions
   landing independently of the control interface. This is a conversation, not
   a patch, and it should happen before B is written.
3. **Decide L1 vs L3 scope** (§4) — this is the user's call and it changes the
   size of the work by roughly an order of magnitude.
4. Then A1.

Nothing is written yet, deliberately: the sequencing above is worth more than a
head start on code that may need a different API shape.
