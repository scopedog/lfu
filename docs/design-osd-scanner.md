# LFU OSD API Input Scanner — Detailed Design

**Module:** `lfu_input_osd` — the **chosen** MDT Input Scanner (Artem, 2026-08-05).
**Parent architecture:** [`architecture.md`](architecture.md) §6b; module contract
in §1, build-order step 6 in §12.
**Sibling:** [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) — Option 1,
the userspace libext2fs device scanner, now the *alternative* path.
**Status:** design proposal, v0.1. Prototype exists for Option 1 only.

Code references are to `../lustre-release` @ `v2_17_55-2-gd717692511`.

---

## 1. Decision and scope

Two approaches were identified in the HLD. **Option 2 — the in-kernel OSD API
scanner via `dt_it_ops`, reusing the OI Scrub iterator — has been chosen.**

Scan the MDT/OST by driving the running OSD's object-table iterator from inside
the server, emitting an Object Stream to userspace Filter Rule and Output Format
modules through a lockless ring buffer.

### 1.1 Evidence from the Option 1 prototype supporting this choice

The Option 1 device scanner was built and run against the lab MDT
(`design-ldiskfs-scanner.md` §17). Three of its measured results bear directly
on the decision, and each one is a con of Option 1 that Option 2 removes:

| Measured on Option 1 | Consequence | Option 2 |
|---|---|---|
| Under create-heavy load, **up to ~50% of allocated inodes** read back inconsistent (`mode` valid, `nlink=0`, `dtime=0`) — mid-creation on-disk state | Artem's "stale by tens of seconds" con is real and much larger than the HLD's "tiny fraction" | Reads **in-memory** inodes; the state never exists — but see the qualification below |
| **`metadata_csum` is OFF** on Lustre MDTs (only `uninit_bg`) — no inode checksums exist | Torn reads can only be detected heuristically, and an inode caught mid-update with plausible `nlink` is emitted with wrong attributes, undetectably | No torn reads to detect |
| **LMA cannot identify all internal objects** — `/CONFIGS/mountdata` and `/update_log_dir/*` carry `compat=0 incompat=0` and leak into "visible" | Needs a hand-maintained inode denylist (*Internal-object exclusion*) | `osd_iit_iget()` **already** skips the backend root, remote-parent and project-quota inodes (`osd_scrub.c:667-677`) — the OSD knows its own local objects |

> **Qualified 2026-08-16 — the first row is weaker than it reads.** Block
> parsing (`blockparse-2026-08-16.md`) removed `ldiskfs_iget()` from the
> `DOIF_PARALLEL` path, so that path no longer reads a live `struct inode`: it
> reads inode-table blocks through the buffer cache. Those blocks are updated at
> `ldiskfs_mark_inode_dirty()` time, not at writeback, so what the scan sees is
> much fresher than "on disk" — but it is **not** the in-memory `struct inode`,
> and the mid-creation window is therefore not provably closed the way it was on
> the iget path. The scrub path is unaffected. Measuring where this bites under
> create-heavy load is an open item (§12); until then, "the state never exists"
> should be read as "the state is far narrower, and unquantified".

The Option 1 work is not wasted. Everything above the device layer transfers
unchanged: the object classification ladder, the attribute cost tiers, the
cost-ordered filter evaluation, the record contents, and the `lfs find`
cross-check methodology. This document reuses them by reference rather than
restating them.

Option 1 also remains genuinely useful for two cases Option 2 cannot serve:
**old servers with no LFU kernel support**, and **offline analysis of an
unmounted MDT or a snapshot**. It should be kept, not deleted.

---

## 2. What already exists — the free part

`dt_otable_features` (`dt_object.h:370`) presents the OSD object table as an
ordinary DT index with a standard `dt_it_ops` iterator. It is implemented by
**all three OSDs**:

| OSD | Implementation |
|---|---|
| ldiskfs | `osd-ldiskfs/osd_scrub.c:2760-2960` |
| ZFS | `osd-zfs/osd_scrub.c:1746-1817` |
| WBCFS | `osd-wbcfs/osd_object.c:32-78` |

### 2.1 The established usage pattern

LFSCK is the only current consumer, and its loop (`lfsck/lfsck_engine.c:978-1062`,
setup at `lfsck/lfsck_lib.c:3724`) is the template:

```c
rc  = obj->do_ops->do_index_try(env, obj, &dt_otable_features);
iops = &obj->do_index_ops->dio_it;

di  = iops->init(env, obj, args);        /* args = valid | (flags << 16) */
rc  = iops->load(env, di, cookie);       /* resume from a stored position */
do {
        rc = iops->rec(env, di, (struct dt_rec *)&fid, 0);
        cookie = iops->store(env, di);   /* checkpoint position */
        ...
        rc = iops->next(env, di);
} while (...);
iops->fini(env, di);
```

Iteration arguments are the 32-bit `attr` of `init()`: low 16 bits
`enum dt_otable_it_valid`, high 16 bits `enum dt_otable_it_flags`
(`dt_object.h:1845-1876`). `DOIF_RESET` restarts at the device beginning;
`DOIF_OUTUSED` marks an out-of-OSD consumer; `DOIF_DRYRUN` scans without repair —
already the semantics a read-only scan wants.

### 2.2 What we get for free

- **Batching and flow control.** `osd_otable_it_preload()` (`osd_scrub.c:1193`)
  fills a 64-entry cache (`OSD_OTABLE_IT_CACHE_SIZE`, `osd_internal.h:206`), and
  `osd_otable_it_next()` coordinates with the background scrub thread via
  `wait_var_event` (`osd_scrub.c:2898`). The producer/consumer rate-matching
  problem is already solved.
- **Checkpoint/resume.** `store()`/`load()` give a position cookie.
- **Internal-object filtering.** `osd_iit_iget()` skips the backend root object,
  the remote parent, and the project quota inode — the *Internal-object exclusion* problem, solved.
- **Backend independence.** One code path for ldiskfs, ZFS and WBCFS.
- **Shared optimisation.** Improvements to the iterator benefit LFSCK too, which
  the HLD explicitly calls out.

---

## 3. The central problem: the iterator returns FIDs only

**This is the main new engineering in Option 2, and it is not a detail.**

`osd_otable_it_rec()` yields exactly one thing — a FID:

```c
/* osd-ldiskfs/osd_scrub.c:2922 */
static int osd_otable_it_rec(const struct lu_env *env, const struct dt_it *di,
                             struct dt_rec *rec, __u32 attr)
{
        *(struct lu_fid *)rec = ooc->ooc_cache[ooc->ooc_consumer_idx].oic_fid;
        return 0;
}
```

ZFS is identical (`osd-zfs/osd_scrub.c:1746`). **Both ignore the `attr`
argument entirely.** The iterator's cache entry (`struct osd_idmap_cache`) holds
only `oic_fid` and `oic_lid` (the inode number/generation).

LFU needs attributes — size, blocks, times, uid/gid/projid, mode, layout, linkea.
The naive path is, per object:

```
iops->rec()            -> FID
dt_locate(env, dt, fid) -> lu_object_find(): FID->OI lookup, hash, alloc, LRU insert
dt_attr_get()           -> re-read the inode
dt_xattr_get()          -> LOV / linkea
lu_object_put()         -> LRU churn
```

Two things make this unacceptable:

1. **It re-does work already done.** `osd_iit_iget()` (`osd_scrub.c:656`) already
   calls `osd_iget()` and instantiates a full `struct inode` in order to read
   `trusted.lma` and recover the FID — then throws the inode away, keeping only
   the FID. The attributes were in hand and discarded.
2. **It churns the object cache.** Instantiating an `lu_object` per scanned
   object, at target rates of ~1M objects/sec, would push the MDS's own working
   set out of the LU object cache and the inode cache. That converts a background
   scan into a foreground performance regression — the exact opposite of the
   feature's purpose.

Artem's stated con, "small overhead per inode from kernel object layer vs raw
block read", is the right concern but understates it if the object layer is
entered per object. **The fix is not to enter it at all.**

> **Extended 2026-08-16.** Point 1 turned out to understate its own case. Not
> entering the *LU object* layer was necessary but not sufficient: the
> `struct inode` that `osd_iit_iget()` instantiates is itself the wall, because
> `iget_locked()` hashes it under the kernel-wide `inode_hash_lock` — 83% of
> eight threads spinning, warm, and a dependent 4 KiB read per inode-table block,
> cold. An enumerator wants a FID and some attributes, and both are already in
> the inode-table block: the FID in `trusted.lma` in the in-inode xattr area, the
> attributes in the raw inode fields. `osd_iit_iget_raw()` maps the block with
> `sb_bread()`, keeps the buffer across `next()` calls, and never builds an
> inode; anything it cannot decode returns `-EAGAIN` and repeats through
> `osd_iit_iget()`, so the object set is identical by construction. Measured at
> **17.4M obj/s warm (10.4×)** and, with an explicit readahead window,
> **1,420,664 obj/s cold at 99% of an NVMe stripe** — see
> `blockparse-2026-08-16.md`. So the sentence above generalises: the fix is not
> to enter the object layer *or the inode cache* at all.

### 3.1 Proposal: extend `rec()` via its existing `attr` argument

`dt_it_ops::rec()` already takes a `__u32 attr` whose documented purpose is to
"ask the iterator to return part of the records" — and there is precedent: the
**directory** iterator uses it with the `LUDA_*` flags (`lustre_idl.h:392-409`,
`LUDA_FID`, `LUDA_TYPE`, …) to select record content.

The otable iterator ignores `attr`. That is the extension point, and using it
means **no new vtable, no new feature struct, and no change to LFSCK**, which
passes `0` and keeps getting a bare FID.

Sketch:

```c
/* New attr flags for otable-based iteration, mirroring LUDA_*. */
enum lfu_otable_attr {
        LFUA_FID        = 0x0001,  /* FID only — the legacy behaviour (attr == 0) */
        LFUA_ATTR       = 0x0002,  /* struct lu_attr: mode, uid, gid, projid,
                                    * size, blocks, atime/mtime/ctime, nlink */
        LFUA_LMA_FLAGS  = 0x0004,  /* lma_compat / lma_incompat */
        LFUA_LAYOUT     = 0x0008,  /* trusted.lov */
        LFUA_LINKEA     = 0x0010,  /* trusted.link */
        LFUA_HSM        = 0x0020,  /* trusted.hsm */
};

struct lfu_otable_rec {
        struct lu_fid   lor_fid;
        __u32           lor_valid;      /* which LFUA_* are actually present */
        __u32           lor_lma_compat;
        __u32           lor_lma_incompat;
        struct lu_attr  lor_attr;
        /* variable-length TLV tail: layout, linkea, hsm */
};
```

The OSD side captures what the caller asked for **inside `osd_iit_iget()`, while
the inode is already instantiated**, and stores it in the iterator cache
alongside the FID. `rec()` then copies it out. The expensive object-layer path is
never entered.

This makes the attribute cost tiers of `design-ldiskfs-scanner.md` §6 apply
almost unchanged — tier 0 and tier 1 are free because the inode is in hand;
tier 2 (external EA block, `ea_inode`) still costs an extra read.

**Cost of the proposal:** the iterator cache grows from
`OSD_OTABLE_IT_CACHE_SIZE × sizeof(osd_idmap_cache)` to something substantially
larger. At 64 entries with, say, 512 bytes per record that is 32 KiB per active
iterator — acceptable, but the cache size may want to become a function of the
requested attribute set rather than a fixed 64.

### 3.2 Alternatives considered

| Option | Verdict |
|---|---|
| `dt_locate()` + `dt_attr_get()` per FID | **Rejected** — §3, object-cache churn and duplicated inode reads |
| A separate `dt_lfu_features` index type with its own vtable | Rejected — duplicates the otable implementation three times over; diverges from LFSCK so shared optimisations stop being shared |
| A new OSD-private API outside `dt_it_ops` | Rejected — loses backend independence, which is the main reason Option 2 was chosen |
| Extend `rec()` via `attr` (§3.1) | **Chosen** — additive, backward compatible, one implementation per OSD, LFSCK untouched |

---

## 4. Filter pushdown in kernel

The requirements and HLD both put filtering at the source. In Option 2 the
filter evaluates **in kernel**, immediately after `rec()`, before the record
enters the ring.

The cost-tier ordering from `design-ldiskfs-scanner.md` §7 carries over intact
and matters more here, because the ring is the scarce resource: an object
rejected by a tier-0 predicate should never cause a tier-2 xattr fetch, and
should never consume ring space.

Design constraints specific to kernel context:

- **Bounded and non-allocating.** A filter program must be verifiable as
  terminating with no loops and no unbounded xattr fetches, and must evaluate
  without allocating. Fixed opcode set for v1; design the opcodes so an eBPF
  backend can slot in later without changing the UAPI.
- **Two tiers, as in Option 1.** Predicates the kernel cannot evaluate (path
  patterns, uid→name) return as **residue** for `liblfu` to apply in userspace,
  transparently, so consumers see one filter.
- **The filter program is UAPI.** It crosses the kernel boundary and, per the
  HLD, third-party tools may generate it. It needs versioning and protocol-flag
  negotiation from day one.

This is the **"Filter cost tiers"** question (`design-ldiskfs-scanner.md` §15) and it is
unchanged and still unanswered: the filter API must expose each predicate's cost
tier, or the ordering optimisation is impossible.

---

## 5. Object Stream export — the ring buffer

The HLD names the Linux Circular Buffer Interface (`circ_buf.h`). **Lustre
already has a working implementation of exactly this pattern in tree:**
`lustre/ofd/ofd_access_log.c` (713 lines) exports the OST access log from kernel
to userspace.

Copy its structure rather than invent one:

| `ofd_access_log.c` | Reuse for LFU |
|---|---|
| `struct circ_buf` + `CIRC_SPACE()` / `CIRC_CNT()` | yes |
| `smp_store_release(&circ->head, …)` / `smp_load_acquire(&circ->head)` | yes — the memory-ordering discipline is already right |
| `miscdevice` + `file_operations` with `.read` and `.poll` | yes — gives `poll()`-driven userspace consumers for free |
| A per-consumer `oal_circ_buf` on a list, so several readers each get their own ring | **no — see §5.1.** The list-of-consumers structure is right, but LFU shares one buffer between them rather than giving each its own (Dilger, 2026-08-06) |
| Separate control device (`oal_control_fops`) from data devices | yes — see §6 |

### 5.1 Three deliberate divergences

**Drop vs. stall.** `oal_write_entry()` (`ofd_access_log.c:145-168`) increments
`ocb_drop_count` and returns `-EAGAIN` when the ring is full. That is correct for
an access *log* — a sampled diagnostic where a gap is harmless. **It is wrong for
a namespace enumeration**, where a silently dropped record makes an incomplete
listing look complete, and a consumer that deletes or migrates things acts on it.

LFU should **stall the producer** by default (the scan is a background job; slowing
it is free), and where dropping is unavoidable set an explicit `LFU_REC_GAP`
marker in the stream so the consumer knows its view is incomplete. Never drop
silently. This mirrors the skip-counting discipline that the Option 1 prototype
proved valuable.

**One buffer, many consumers — not one ring each.** (Dilger, 2026-08-06.) The
access log gives every reader its own `oal_circ_buf`; for LFU that would be
correct only if each consumer drove its own scan. It does not: the point of
fan-out is that **one** scan's IO serves all of them. Duplicating the ring per
consumer duplicates neither the IO nor the scan, but it does duplicate the
record memory and the copy, for no gain. LFU keeps the list-of-consumers
structure and gives each consumer its own **read cursor into a shared buffer**.

This collides with the stall rule above, and the collision needs an explicit
policy (**"Slow consumers"**, `open-questions.md`): with a shared buffer, reclaim is gated by
the *slowest* consumer, so "stall the producer" means one slow consumer stalls
the scan for everyone. The options are stall-on-slowest (correct, but a hung
consumer becomes a hung scan — needs a timeout that evicts rather than blocks),
or advance past a lagging consumer and hand it an `LFU_REC_GAP`. The invariant
that must not bend either way: **a consumer is always told when its view is
incomplete.** Note this argument is transport-level and applies to the Option 1
userspace scanner too, where nothing prevents N concurrent scans — it is simply
wasteful to run them.

**"Zero-copy" is aspirational as written.** The precedent uses `.read`, which
copies from the ring into the user buffer — one copy. Genuine zero-copy needs
`.mmap` of the ring pages, with head/tail in a shared control page. That is
worth doing, but it is strictly more work and more attack surface, and it should
be measured against the `read()` path before committing. Note the requirements
page ranks zero-copy export only **Medium**, below the scanner itself — so
shipping the `read()` path first is legitimate, and the record format must not
change when the transport does.

---

## 6. Control plane

A scan needs start / stop / status / attribute-mask / filter-program / consumer
registration. Options, in order of preference:

1. **Netlink** — the direction of travel for Lustre (LU-19768, "Efficient NetLink
   interface to Lustre statistics", TLC, is on the same roadmap), structured,
   extensible, and already how modern Lustre configuration is heading.
2. **A control character device** alongside the data devices, exactly as
   `oal_control_fops` / `oal_control_misc` (`ofd_access_log.c:659-681`) does.
   Lowest-friction, proven in tree, and keeps LFU self-contained.
3. `lctl set_param` / procfs — simplest, but a poor fit for passing a binary
   filter program.

Recommend (2) for v1 because it is the smallest step from working precedent, with
(1) as the target once the netlink infrastructure lands.

**Deliberately *not* an MDT RPC in v1.** The MDT handler table
(`mdt_tgt_handlers[]`, `mdt/mdt_handler.c:6292`) is where a remote scan RPC would
eventually be registered, and the HLD's Server Bulk RPC Filter Rule Module needs
it — but that is a later phase (`architecture.md` §12 step 7), gated on
`OBD_CONNECT2_LFU` negotiation and access control. A server-local consumer needs
no RPC at all, and phase 1 is server-only.

---

## 7. Module placement and lifecycle

Artem's note says the scanner "adds code to `mdt.ko`". Consider instead a
separate **`lfu.ko`**:

- The scanner is not MDT-specific — the same code must serve OSS/OFD targets, and
  putting it in `mdt.ko` forces either duplication or an awkward dependency.
- It can be loaded only where LFU is wanted, so sites that do not use it pay
  nothing and carry no added attack surface in the MDS.
- `dt_otable_features` is an `obdclass`/OSD-level interface; a consumer of it does
  not belong in the MDT layer.
- It keeps the "no flag day" property: LFU can be added to a running server by
  loading a module.

The counter-argument is that the eventual bulk-RPC path *does* live in the MDT
handler, and splitting creates a `mdt.ko` → `lfu.ko` dependency. That is a real
cost but a small one, and it can be a weak/optional dependency since the RPC path
is a later phase. **Recommend `lfu.ko`; flag as a decision to confirm.**

### Kernel execution context

- Scans run in a dedicated kthread per target, not in a service thread — a scan
  is long-running and must never occupy an MDS request slot.
- Each needs its own `lu_env` / `lu_context` (`lu_env_init()`), as LFSCK's engine
  threads do.
- Stop must be cooperative and prompt: check `kthread_should_stop()` in the
  iteration loop, exactly as `osd_scrub_next()` does (`osd_scrub.c:754`).

---

## 8. Coexistence with LFSCK and OI Scrub

This is the sharpest operational risk in Option 2, and it is new relative to
Option 1 (which simply competed for device bandwidth from outside).

### 8.1 The otable iterator is a per-device singleton **[confirmed in code]**

`osd_otable_it_init()` (`osd-ldiskfs/osd_scrub.c:2760`) opens with:

```c
/* od_otable_mutex: prevent curcurrent init/fini */
mutex_lock(&dev->od_otable_mutex);
if (dev->od_otable_it != NULL)
        GOTO(out, it = ERR_PTR(-EALREADY));
```

There is exactly one `od_otable_it` per `osd_device`, and a second `init()`
fails with **`-EALREADY`**. This is not a soft constraint to design around; it is
enforced.

Three consequences, all of which shape the module:

1. **An LFU scan and an LFSCK run cannot coexist on a target.** Whichever starts
   second gets `-EALREADY`. On a large filesystem LFSCK can run for hours or
   days, during which LFU cannot scan at all. This needs to be stated plainly to
   users and to Andreas — it may be acceptable, but it must not be a surprise
   discovered in production.
2. **Two concurrent LFU scans on one target are impossible.** Different consumers
   wanting different filters cannot each open their own iterator.
3. **Therefore the fan-out layer is mandatory, not an optimisation.** The HLD's
   "one scan feeds multiple consumers simultaneously" is the *only* way to serve
   more than one consumer. It must exist in v1, and the filter/consumer model
   must support attaching several filter programs to a single pass rather than
   assuming one scan per query.

LFU must handle `-EALREADY` deliberately: refuse with a clear diagnostic naming
the current holder, or queue behind it — not retry blindly.

> **Revised 2026-08-15, measured** — the singleton binds the otable iterator
> *object*, not the inode-table walk. `DOIF_PARALLEL`
> (`parallel-osd-scanner-2026-08-15.md`) adds a private iterator instance that
> is never registered as `od_otable_it` and never starts the scrub, so N of
> them walk N inode ranges concurrently. Consequences 1–3 above hold for the
> *default* iterator only.
>
> `parallel-osd-measured-2026-08-15.md`: **ldiskfs 2.03M obj/s at 2 threads vs
> the singleton's 853k** (2.4×) and **ZFS 561k at 16 vs 154k** (3.64×, and
> 2.5× the userspace ZFS device scanner on the same pool), identical FID set
> and attributes on both backends;
> and, with a verifying OI scrub running, the private iterator returned the
> full namespace at **1.41M obj/s while the singleton got `-EALREADY`**, with
> the scrub finishing undisturbed. Consequence 1 (LFU and LFSCK cannot
> coexist) is therefore **resolved**; consequence 3's fan-out layer is still
> wanted for one-scan-N-consumers, but no longer because parallelism is
> impossible.
>
> **Updated 2026-08-16.** The ldiskfs half of those numbers was itself bounded by
> `ldiskfs_iget()`, not by the sharding. With block parsing on the private path
> (`blockparse-2026-08-16.md`) ldiskfs reaches **17.4M obj/s warm at 4 threads**
> and **1,420,664 cold at 99% of an NVMe stripe** — parity with the userspace
> device scanner. The private path now peaks at four threads rather than two,
> because the box goes idle before the lock does.

The clean long-term resolution is the HLD's own suggestion, that LFSCK become an
Object Stream consumer too, so there is one iterator with LFSCK and LFU both
downstream of it. Out of scope here, but §3.1's API must not preclude it.

### 8.2 Remaining coexistence questions

- **Whose checkpoint state?** LFU must not disturb the scrub bookmark that OI
  Scrub and LFSCK rely on for their own restart position.
- **Who arbitrates bandwidth?** LFSCK has a speed limit; LFU needs an equivalent
  throttle. Less urgent than it appeared, since §8.1 means they cannot run
  concurrently anyway — but a scan still competes with live client traffic.

The HLD's suggestion that LFSCK might itself be restructured as an Object Stream
consumer is the clean long-term answer — one scan, many consumers, with LFSCK
just another one. That is out of scope here but the API should not preclude it.

---

## 9. Backend differences

| Backend | otable | Notes |
|---|---|---|
| **ldiskfs** | `osd_scrub.c:2760-2960` | Inode bitmap walk; the reference implementation. The §3.1 attribute capture goes in `osd_iit_iget()` — and, since 2026-08-16, in `osd_iit_iget_raw()`, which reads both FID and attributes straight out of the inode-table block on the `DOIF_PARALLEL` path |
| **ZFS** | `osd-zfs/osd_scrub.c:1746-1817` | `rec()` identical (FID only, ignores `attr`). Attribute capture must be implemented separately — dnode traversal, no inode bitmap |
| **WBCFS** | `osd-wbcfs/osd_object.c:32-78` | Already provides `do_attr_get` on the otable object. Artem's pro-list omits WBCFS; confirm whether it is in scope |

The §3.1 API extension must be specified once and implemented per backend. A
backend that does not implement a requested `LFUA_*` flag must report it as
absent in `lor_valid` rather than failing — the HLD's required/optional
attribute distinction applies here directly.

---

## 10. What Option 2 does *not* fix

Honesty about the remaining risks, since Option 1's cons are now well measured
and Option 2's are not:

- **Scans still see a fuzzy snapshot.** In-memory metadata is current, but the
  scan is not atomic with respect to concurrent modification. Objects created
  during the scan may or may not appear. Consumers must still tolerate this.
- ~~**Cost moves rather than disappearing.**~~ **Answered 2026-08-16.** The
  concern was that Option 1 reads the inode table sequentially at device
  bandwidth while Option 2 goes through `osd_iget()`, i.e. the VFS inode cache,
  per object — and that this was the single biggest open technical risk. It was
  the right risk: `iget` bounded both the warm and the cold path. It is no longer
  taken. On the `DOIF_PARALLEL` path the scanner reads the inode table
  sequentially too, and measures **1,420,664 obj/s cold at 99% of an NVMe
  stripe** against the device scanner's 1,439,300 on the same stripe — 0.99×.
  Against the HLD's 1-hour, 4-billion-object target: **0.78 h**. What remains of
  this bullet is the CPU and cache cost on the MDS, which is the next bullet.
- **The MDS pays.** The scan now runs inside the server, consuming its CPU,
  memory and inode cache. §3's whole purpose is to keep that cost bounded, but it
  cannot be zero, and it must be measured under concurrent client load.
- **Filter code now runs in kernel** — a parsing and evaluation surface in the
  most privileged context. `design-ldiskfs-scanner.md` §12 argued for
  fuzz-testing the userspace parser; here it is not optional.

---

## 11. Testing

| Test | Method |
|---|---|
| Enumeration completeness | **Reuse the Option 1 methodology** (`design-ldiskfs-scanner.md` §17): scanner FID set vs. `lfs find` + `lfs path2fid`. It found 0 misses for Option 1 and is the primary oracle |
| Cross-check Option 1 vs Option 2 | Run both against the same quiescent MDT; the visible FID sets must be identical. This is a strong differential test that neither has alone |
| Attribute correctness | Compare `LFUA_ATTR` output against `stat`/`lfs getstripe` per FID |
| Internal objects excluded | Assert `/CONFIGS/*`, `/update_log_dir/*`, OI files and quota files are absent — Option 1 leaks 3 of these (*Internal-object exclusion*); Option 2 should leak none |
| Live-load consistency | The Option 1 load harness showed ~50% inconsistency; Option 2 should show **zero** skipped/invalid records under the same load. This is the headline claim and must be demonstrated |
| LFSCK coexistence | Start LFSCK and an LFU scan together; assert defined behaviour (either both progress, or one is cleanly refused) |
| Ring backpressure | Slow consumer; assert producer stalls and **no records are lost**, or `LFU_REC_GAP` is set |
| Object-cache impact | Measure MDS `lu_object` / inode cache hit rates and client metadata latency during a scan |
| Filter pushdown | Same predicate as pushdown vs. userspace post-filter; identical results |
| Backend parity | Same test suite against ldiskfs and ZFS targets |

The lab cluster (`notes/reference/cluster_setup.md`) supports all of the above
except throughput at realistic scale.

---

## 12. Open questions

| Topic | Question | Blocks |
|---|---|---|
| ~~Iterator singleton~~ | **Resolved twice.** Yes, a strict singleton (`-EALREADY`, §8.1) — for the *default* iterator. **2026-08-15:** `DOIF_PARALLEL` private instances sidestep it entirely, measured at 2.03M obj/s on 2 threads and concurrent with a running OI scrub (`parallel-osd-measured-2026-08-15.md`). The fan-out layer stays wanted for one-scan-N-consumers, not for parallelism | — |
| ~~**LFSCK coexistence**~~ | **Resolved 2026-08-15 by measurement** — a `DOIF_PARALLEL` scan ran to completion at 1.41M obj/s *while* a verifying OI scrub was scanning, and the scrub finished with `updated: 0, failed: 0`. The question was "is blocking acceptable"; the answer is that it no longer blocks | — |
| **Upstream API change** | Is the §3.1 `rec()`/`attr` extension acceptable to upstream, or is a new index feature preferred? | The core API change |
| **Cost to existing users** | Can `osd_iit_iget()` capture attributes without materially slowing OI Scrub and LFSCK, which share the path? | Whether §3.1 is free or a tax on existing users |
| ~~**Scan throughput**~~ | **Resolved 2026-08-16.** The question was whether the OSD path reaches 1M objects/sec/MDT. History: 2026-08-06 measured the unmodified iterator at **105k obj/s** against the device scanner's 705k (6.7×, a "blocker" under the `throughput-test-plan.md` §3 gate); 2026-08-15 `DOIF_PARALLEL` took ldiskfs to **2.03M warm**; 2026-08-16 block parsing took it to **17.4M warm and 1,420,664 cold at 99% of an NVMe stripe**, against the device scanner's 1,439,300 on the same stripe — **ratio 1.01**, and 0.78 h against the HLD's 4-billion-object hour. The 6.7× gap is closed. *What it costs the MDS under client load is still open* — see the next row | — |
| **Foreground impact** | What does a scan at these rates cost the MDS under concurrent client load? (§10) | The top remaining risk. A mounted client already costs ldiskfs warm ~20%; enumerators now run fast enough that the question is no longer academic. Nothing ships on throughput numbers alone |
| **Freshness after block parsing** | Block parsing reads inode-table blocks through the buffer cache, not the live `struct inode` (§1.1). How stale is that under create-heavy load, and does it re-open the torn/mid-creation exposure Option 2 was chosen to avoid? | Whether the §1.1 row 1 advantage over Option 1 survives as stated |
| **Inode checksum** | The raw parse does not verify the inode metadata checksum, so it *reports* a corrupt inode where `ldiskfs_iget()` refuses it. Defensible for a scanner whose consumer re-reads before acting — but it belongs in the API contract, not a code comment | The Object Stream contract |
| **Module layout** | `lfu.ko` or code in `mdt.ko`? (§7) | Packaging and dependencies |
| **Backend coverage** | Is WBCFS in scope? (§9) | Which backends v1 serves |
| **Transport scope** | `read()` ring first, or `mmap` zero-copy from the start? (§5.1) | How much of the export lands in v1 |
| **Filter cost tiers** | Can the filter API expose per-predicate cost tiers? (§4) | Pushdown ordering — carried over, still unanswered |

**"Cost to existing users" is answerable by reading code now** and should be
settled before anything is written.

**Scan throughput was the biggest technical risk. It is now closed** — and the
sequence is worth keeping, because the first answer was wrong about the cause.
2026-08-06 measured 105k obj/s against Option 1's 705k and called the per-object
kernel path the limit, with the iterator singleton blocking the parallelism that
would close it. The singleton turned out not to be the limit either
(`DOIF_PARALLEL`, 2.03M warm), and neither was "the kernel": it was one call,
`ldiskfs_iget()`, on both the warm and the cold path. Removing it left the
in-kernel scanner at **1.01× the userspace device scanner cold**. Two lessons
generalise past this module: a ceiling attributed to an architecture was twice
attributable to a single call, and each time the evidence that settled it was a
control row on the same build.

**Attention now belongs on foreground impact under client load**, which no
throughput number addresses, and on the two correctness items the block parse
introduced (freshness, inode checksum). "LFSCK coexistence" is resolved as a
technical matter but remains a conversation to have early with upstream.

---

## References

Verified against `../lustre-release` @ `v2_17_55-2-gd717692511`:

- `lustre/include/dt_object.h:370` — `dt_otable_features`
- `lustre/include/dt_object.h:1845-1876` — `dt_otable_it_valid` / `_flags`, `DT_OTABLE_IT_FLAGS_SHIFT`
- `lustre/include/dt_object.h` — `struct dt_it_ops` (`init`/`get`/`put`/`next`/`rec`/`store`/`load`/`fini`)
- `lustre/osd-ldiskfs/osd_scrub.c:656` — `osd_iit_iget()`, inode instantiation + LMA read; internal-object skips at :667-677
- `lustre/osd-ldiskfs/osd_scrub.c:1193` — `osd_otable_it_preload()`
- `lustre/osd-ldiskfs/osd_scrub.c:2760-2960` — ldiskfs otable iterator; `rec()` at :2922
- `lustre/osd-ldiskfs/osd_internal.h:206-231` — `OSD_OTABLE_IT_CACHE_SIZE`, `osd_otable_cache`
- `lustre/osd-zfs/osd_scrub.c:1746-1817` — ZFS otable iterator
- `lustre/osd-wbcfs/osd_object.c:32-78` — WBCFS otable support
- `lustre/lfsck/lfsck_lib.c:3724` — `do_index_try(&dt_otable_features)`
- `lustre/lfsck/lfsck_engine.c:978-1062` — the canonical iteration loop
- `lustre/ofd/ofd_access_log.c` — **the in-tree `circ_buf` kernel→userspace precedent**; ring write at :133-168, fops at :435-442, control device at :659-681
- `include/uapi/linux/lustre/lustre_idl.h:392-409` — `LUDA_*`, the attr-driven record precedent
- `lustre/mdt/mdt_handler.c:6292` — `mdt_tgt_handlers[]`, where a future scan RPC registers
