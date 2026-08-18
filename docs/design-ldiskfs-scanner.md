# LFU ldiskfs Device Input Scanner — Detailed Design

**Module:** `lfu_input_ldiskfs` — the initial LFU Input Scanner Module.
**Parent architecture:** [`architecture.md`](architecture.md) §6a; module contract
in §1, build-order step 3 in §12.
**Sources:** `reference/lfu-hld.pdf` §"ldiskfs Device Input Scanner Module";
`reference/lug2026-lustre-218-and-beyond-dilger.pdf` slide 21.
**Status:** design proposal, v0.1. No code yet.

Code references are to `../lustre-release` @ `v2_17_55-2-gd717692511`.

---

## 1. Purpose and scope

Generate an LFU Object Stream by reading MDT (and OST) metadata **directly from
the block device in userspace, via libext2fs**, at device read bandwidth. This
replaces client-side `lfs find` traversal for the initial rollout.

It follows `e2scan` and Lester, the Lustre Lister. It runs independently of the
MDS/OSS service and needs only **read-only** access to the underlying block
device.

### In scope

- Full-device enumeration of ldiskfs inodes on an MDT or OST
- FID recovery and object classification from Lustre xattrs
- Attribute extraction into an Object Stream, driven by a caller-supplied mask
- Pushed-down filter evaluation, ordered by I/O cost
- Parallel scan within one device; checkpoint and restart

### Out of scope

- **Repair of any kind.** LFU reads; LFSCK and OI Scrub repair. The scanner has
  no write path and opens the device `O_RDONLY`.
- Pathname construction — an Output Format concern (`architecture.md` §7, *Path resolution priced separately*),
  though this module emits the linkea bytes that make it possible.
- Cross-target merge — a Filter Rule concern, server-side (§1, *Merge location*).
- ZFS and WBCFS backends — those are served by the OSD API Input Scanner
  (`architecture.md` §6b), which is why that module exists.

### Why this module first

It requires **no kernel changes and no Lustre server modification**, so it works
against unmodified existing servers. That is what makes the "no flag day"
rollout real. See `architecture.md` §6a.

---

## 2. Interface contract

As an LFU Input Scanner Module (`architecture.md` §1), it is defined entirely by
the Object Stream it produces and the request it accepts.

### 2.1 Request

```c
struct lfu_scan_ldiskfs_req {
        const char        *lsr_device;      /* block device path, O_RDONLY   */
        __u64              lsr_attr_mask;   /* LFU_ATTR_* required           */
        __u64              lsr_attr_opt;    /* LFU_ATTR_* optional           */
        struct lfu_filter *lsr_filter;      /* pushed-down predicates, or NULL */
        __u32              lsr_nr_threads;  /* 0 = auto                      */
        __u64              lsr_start_ino;   /* resume point, 0 = beginning   */
        __u32              lsr_flags;       /* LFU_SCAN_*                    */
};
```

`lsr_attr_mask` vs `lsr_attr_opt` implements the HLD's required/optional
distinction: an optional attribute is emitted when it is cheap to obtain and
omitted otherwise, and consumers must tolerate its absence. For this module the
rule is concrete and is defined by the cost tiers in §6.

### 2.2 Emitted object

One Object Stream record per accepted object. Logical content — physical
encoding is the LFU Object Stream format, not this module's concern:

| Field | Source | Tier (§6) |
|---|---|---|
| FID | `trusted.lma` → `lma_self_fid` | 1 |
| object type / mode, nlink | `i_mode`, `i_links_count` | 0 |
| uid, gid | `i_uid`+`i_uid_high`, `i_gid`+`i_gid_high` | 0 |
| projid | `i_projid` (extended inode) | 0 |
| size | `i_size_lo`/`i_size_high` | 0 |
| blocks | `i_blocks_lo` + `l_i_blocks_high` | 0 |
| atime, mtime, ctime, crtime | inode + `*_extra` | 0 |
| inode flags, generation | `i_flags`, `i_generation` | 0 |
| LMA compat/incompat flags | `trusted.lma` | 1 |
| layout (stripe/mirror/comp) | `trusted.lov` | 1 or 2 |
| dir striping | `trusted.lmv` | 1 or 2 |
| linkea (parent FIDs + names) | `trusted.link` | 1 or 2 |
| HSM state | `trusted.hsm` | 2 |
| SOM | `trusted.som` | 2 |
| **source target id** | caller-supplied | — |
| **replica hint** | see §10.3 (LMR) | — |

### 2.3 Control

`start` · `stop` (cooperative, at group boundary) · `progress` (inodes scanned,
emitted, filtered, errored; bytes read) · `checkpoint` (§9).

---

## 3. Operating model

A userspace process on the MDS or OSS node, or on any node with read access to
the target's block device (e.g. a snapshot or a passive failover partner).

- Opens the device **read-only**; no write path exists in the module.
- Does **not** require the target to be unmounted, and does not coordinate with
  the MDS. It may run while the filesystem is mounted and active — with the
  consistency consequences in §8.
- Does not require Lustre kernel modules to be loaded.

### Privilege

Reading a block device requires `CAP_DAC_OVERRIDE` or group membership on the
device node — this exposes **every object's metadata on the target with no
access control whatsoever**, which is precisely why the HLD flags improved
security as an advantage of the OSD API scanner. Consequences:

- This module is an **administrator-only** tool. It must never be reachable by
  the Server Bulk RPC path that serves unprivileged users; that path is served
  by the OSD API scanner with nodemap/RBAC filtering (`open-questions.md` *Access control granularity*).
- Recommend running it under a dedicated system user in the device's group,
  rather than root, so that `O_RDONLY` is enforced by file permissions and not
  merely by convention.
- The emitted stream is as sensitive as the namespace itself. Filenames in
  linkea are user data; where they are written matters.

---

## 4. On-disk structures consumed

Verified against the ldiskfs/ext4 layout and the Lustre OSD code.

### 4.1 ext4 structures

| Structure | Use | Volatility while mounted |
|---|---|---|
| Superblock | geometry, feature flags, inode size, groups | very low |
| Group descriptors | inode table location, `bg_itable_unused` | low |
| **Inode bitmap** (per group) | which inodes are in use | **high** |
| **Inode table** (per group) | the objects themselves | **high** |
| Extended attribute block (`i_file_acl`) | xattrs too large to inline | medium |

Notably **not** read: block bitmaps, extent trees, directory blocks, the journal.
A flat object scan does not need them, and every structure not read is a class of
torn-read exposure avoided (§8.2). Directory contents are needed only for
pathname resolution, which is an Output Format concern and out of scope here.

### 4.2 Lustre xattrs

Names from `include/uapi/linux/lustre/lustre_idl.h:1283-1292`:

| xattr | Contents | Needed for |
|---|---|---|
| `trusted.lma` | `struct lustre_mdt_attrs` — `lma_compat`, `lma_incompat`, `lma_self_fid` | **FID; classification. Required for every object.** |
| `trusted.lov` | LOV layout — stripes, components, mirrors | mirror status, OST membership, pool |
| `trusted.lmv` | directory striping | DNE-aware traversal |
| `trusted.link` | linkea — parent FIDs + names | pathname generation |
| `trusted.hsm` | HSM state | HSM consumer |
| `trusted.som` | Size-on-MDT | size without OST query |

`struct lustre_mdt_attrs` (`lustre_user.h:495`) is 24 bytes: two `__u32` flag
words plus a 16-byte `lu_fid`. On-disk it is little-endian; `osd_get_lma()`
(`osd_handler.c:460`) byte-swaps on read and rejects
`lma_incompat & ~LMA_INCOMPAT_SUPP`. **The userspace scanner must replicate both
the swab and the incompat check** — an unknown incompat bit means the object
cannot be safely interpreted.

### 4.2b Feature flags on a real Lustre target

From `mkfs.lustre` (`libmount_utils_ldiskfs.c:628-700`), an MDT is formatted with
`dirdata`, `mmp`, `dir_nlink`, `quota` + `project`, `huge_file`, **`ea_inode`**,
`large_dir`, `flex_bg`, `uninit_bg`, `64bit`, and **`fast_commit` explicitly
disabled** ("breaks ldiskfs transactions ordering" — one less complication for us).

Three of these directly shape the scanner:

- **`mmp`** (multi-mount protection) is enabled. Opening a device that is mounted
  by the MDS will trip the MMP check. The scanner must open with
  `EXT2_FLAG_SKIP_MMP` — legitimate here because it never writes, but it means
  MMP is not protecting us and read-only discipline must be enforced elsewhere
  (§3).
- **`ea_inode`** is enabled *on MDTs specifically* — "allow xattrs larger than one
  block, stored in a separate inode". This creates a cost tier beyond the
  external EA block; see §6.
- **`dirdata`** is Lustre-originated. Stock upstream libext2fs *defines*
  `EXT4_FEATURE_INCOMPAT_DIRDATA` (0x1000) but **will not open a filesystem that
  has it set** — which means the WhamCloud e2fsprogs fork is a hard requirement.
  Tested; see §14 and `tests/dirdata_probe.sh`.

### 4.3 Why the attributes are cheap — inode sizing

`mkfs.lustre` sizes MDT inodes so Lustre xattrs fit **inline in the inode body**
(`libmount_utils_ldiskfs.c:883-890`):

| Stripe count | MDT inode size |
|---|---|
| ≤ 16 | **1024 B** (default) |
| 17–59 | 2048 B |
| > 59 | 512 B — wide striping goes to external EA blocks regardless |

Inline xattrs live after `EXT2_GOOD_OLD_INODE_SIZE + i_extra_isize` within the
inode itself. With a 1 KiB MDT inode, **LMA + LOV + linkea are typically
retrieved by the same read that fetched the inode** — no additional seek.

This is the load-bearing fact of the whole design, and it is what makes the HLD's
performance target arithmetic work: 1M objects/sec at ≥1 GiB/s is ~1 KiB per
object, which is exactly one default MDT inode. See §11.

Corollary — **the target assumes the default configuration.** A filesystem
formatted for >59 stripes has 512 B inodes and pushes layouts to external EA
blocks, adding a seek per object. That is not an edge case for
layout-filtering workloads; see §6 tier 2 and `open-questions.md` *Does the target survive real filters*.

---

## 5. Object identification and classification

FIDs are recovered from LMA, mirroring `osd_scrub_get_fid()`
(`osd_scrub.c:576`) and `osd_iit_iget()`. Divergence from that ladder means
LFU disagrees with the OSD about what an object *is*, so it is reproduced
deliberately rather than approximated:

```
read trusted.lma
├─ present:
│   ├─ lma_incompat & ~LMA_INCOMPAT_SUPP  → ERROR, count, skip
│   ├─ lma_compat & LMAC_NOT_IN_OI        → internal, skip
│   ├─ lma_incompat & LMAI_AGENT          → agent inode, skip
│   ├─ lma_compat & LMAC_FID_ON_OST       → OST object
│   ├─ fid_is_idif(fid)                   → OST object (≤2.3 style)
│   ├─ fid_is_internal(fid)               → local/internal object
│   ├─ fid_is_namespace_visible(fid)      → EMIT
│   └─ otherwise (normal FID)             → ambiguous MDT/OST, see below
└─ absent (-ENODATA):
    ├─ trusted.fid present                → old OST object
    └─ neither                            → IGIF candidate (pre-2.0 upgrade)
```

Relevant flags (`lustre_user.h:460-484`): `LMAC_NOT_IN_OI`, `LMAC_FID_ON_OST`,
`LMAC_HSM`, `LMAC_STRIPE_INFO`, `LMAC_COMP_INFO`; `LMAI_AGENT`,
`LMAI_REMOTE_PARENT`, `LMAI_STRIPED`, `LMAI_ORPHAN`, `LMAI_ENCRYPT`,
`LMAI_RELEASED`.

Two of these matter to consumers and must reach the stream, not be silently
dropped: **`LMAI_ORPHAN`** and **`LMAI_ENCRYPT`** (see §10.4).

> **`LMAI_RELEASED` is a trap.** It is defined (`0x00000001`) but is **not in
> `LMA_INCOMPAT_SUPP`**, and grep confirms it is never set or tested anywhere in
> v2.17 outside the wire-protocol constant checks. An object carrying it would
> therefore be *rejected as unsupported* by `osd_get_lma()` — and must be
> rejected by the scanner too, for consistency.
>
> HSM released state actually lives in `trusted.hsm` as `HS_RELEASED`
> (`lustre_user.h:2440`), which is a **tier-2** read (§6). So "find released
> files" is not a cheap query, and any consumer that assumes otherwise is
> mispriced.
>
> Found by the prototype: the test image set `LMAI_RELEASED` expecting an
> emitted-and-flagged object and got `bad` instead. The implementation was
> right and this document was wrong.

### 5.1 Device role

MDT vs OST is determined once, at open, from the target's `last_rcvd` / mount
data rather than inferred per object. `osd_scrub_check_local_fldb()`
(`osd_scrub.c:~560`) shows the kernel taking the same shortcut: on an OST, a
normal FID is an OST object.

### 5.1b LMA alone cannot identify every internal object **[measured]**

Running against a real MDT showed the ladder above is *necessary but not
sufficient*. Three objects were classified namespace-visible that are in fact
MDT-internal:

| Object | LMA FID | LMA flags |
|---|---|---|
| `/CONFIGS/mountdata` | `[0xe:0x0:0x0]` — IGIF, seq = its own inode number 14 | `compat=0 incompat=0` |
| `/update_log_dir/[0x200000400:0x1:0x0]` | normal sequence | `compat=0 incompat=0` |
| `/update_log_dir/[0x200000401:0x1:0x0]` | normal sequence | `compat=0 incompat=0` |

**None carries `LMAC_NOT_IN_OI` or any other distinguishing flag.** They are
indistinguishable from user objects by LMA content alone. `osd_scrub_get_fid()`
is a FID-*recovery* function, not a namespace-visibility oracle — the kernel
knows these are internal from directory context, which a flat scan does not have.

The good news is that the leak is **bounded and fixed, not proportional**: the
same 6 extras appeared whether the namespace held 173 or 509 objects (the other
3 are `.lustre`, `.lustre/fid` and `.lustre/lost+found`, which are correctly
visible and merely hidden from `lfs find`).

Fix, for implementation: at scan start, read the ldiskfs root directory once and
collect the inode numbers of the known-internal subtrees — `CONFIGS`,
`update_log_dir`, `O`, `PENDING`, `REMOTE_PARENT_DIR`, `lost+found`, `OI` files,
quota files, `last_rcvd`, `seq`/`fld` — then exclude their contents by inode
number. A handful of directory reads, once per scan, bounded cost. This is
question *Internal-object exclusion*.

**Filed upstream as LU-20602** (2026-08-18): set a compat flag in `trusted.lma`
at creation so the object says what it is, with the initial LFSCK setting it on
existing filesystems. The denylist above remains necessary until that lands and
for filesystems that have not run the new LFSCK, so it is the fix here either
way. Source text: `tickets/lma-internal-objects.md`.

### 5.2 Objects deliberately not emitted

Internal objects are skipped by default (`LFU_SCAN_INTERNAL` overrides, for
debugging): OI files (`oi.16.*`, `OSD_OI_NAME_BASE` at `osd_oi.c:49`), the `O/`
hierarchy on OSTs, `REMOTE_PARENT_DIR`, `PENDING`, quota files (`ADMIN_USR` at
`osd_internal.h:87`), llog catalogs, changelog catalog/users, the LFSCK
bookmark, `lost+found`, and the ext4 reserved inodes (< 11).

Classification is by **FID sequence**, not by name — names are not available in a
flat scan. Sequence ranges are at `lustre_idl.h:278-310`; `FID_SEQ_NORMAL =
0x200000400` is the boundary, with everything below it internal except
`FID_SEQ_ROOT` and `FID_SEQ_DOT_LUSTRE`.

### 5.3 IGIF

Inodes with no LMA on an MDT are pre-2.0 objects predating self-FIDs. The kernel
optionally synthesises an IGIF FID from `i_ino`/`i_generation`
(`lu_igif_build()`), gated on `os_convert_igif`. The scanner does the same, but
**must never write** the synthesised FID back — emit it flagged as synthetic and
let LFSCK own persistence.

---

## 6. Attribute cost tiers

The organising principle for both the emission and the filter ordering (§7).

| Tier | Cost | Contents |
|---|---|---|
| **0** | free — already in the inode buffer | mode, nlink, uid, gid, projid, ~~size, blocks~~, atime/mtime/ctime/crtime, flags, generation |
| **1** | free — inline xattr in the same inode | LMA (FID), and usually LOV, LMV, linkea, **SOM** on a default 1 KiB MDT inode |
| **2** | **one extra random read** — external EA block via `i_file_acl` | large layouts (wide striping, many components/mirrors), long linkea (many hardlinks), HSM, ~~SOM~~ |
| **2b** | **an entire extra inode read** — `ea_inode` | xattrs exceeding one block. Enabled on MDTs by `mkfs.lustre` (§4.2b) |
| **3** | out of scope here | pathname — needs linkea plus a parent-chain walk; Output Format module |

> **Corrected 2026-08-16 — [`filter-levels.md`](filter-levels.md) §4.** Two
> entries above were wrong and are struck through.
>
> **`size` and `blocks` are not tier 0.** An MDT inode's `i_size` is stale or
> zero for a regular file with OST objects, and its `i_blocks` counts the *MDT
> inode's own* blocks — EA blocks and dirdata, single digits — not the file's
> data. `lfs find` handles this explicitly
> (`liblustreapi_pfind.c:2862-2875`): without `OBD_MD_FLSIZE` it falls through
> to a stat that glimpses the OSTs. The MDT can supply the size only from
> `trusted.som`, as `OBD_MD_FLLAZYSIZE` (`mdt_handler.c:874-904`).
>
> **SOM is therefore tier 1, not tier 2.** `lustre_som_attrs` is 24 bytes and
> `mkfs.lustre` counts it in the inline budget alongside LOV, LMA and linkea
> (`libmount_utils_ldiskfs.c:860-890`).
>
> Consequence: an MDT-only scan implements `lfs find --lazy` semantics exactly —
> a supported mode, worth stating rather than apologising for — and a size
> filter gains a third outcome besides match and no-match, **unknown**, for
> objects with no `trusted.som`.

Tier 0 and 1 fit the performance budget; tier 2 and 2b do not. The scanner
therefore tracks and reports a **tier-2 hit rate**, because it is the single
number that predicts whether a given filter meets the target on a given
filesystem.

`i_file_acl != 0` signals an external EA block, testable from the inode with no
additional I/O — so tier-2 avoidance is a decision the filter layer can make
cheaply.

### 6.1 The libext2fs API maps onto this cleanly

Verified against libext2fs 1.47.0 headers:

- `ext2fs_get_next_inode_full(scan, &ino, inode, bufsize)` — returns the **full
  large inode**, including the inline xattr region. Tier 0 comes free from this
  buffer.
- **`ext2fs_xattrs_read_inode(handle, struct ext2_inode_large *inode)`** — parses
  xattrs from an inode buffer *the caller already holds*. This is the tier-1 path
  and is exactly the primitive the design needs.
- `ext2fs_xattrs_open(fs, ino, &handle)` + `ext2fs_xattrs_read(handle)` — the
  by-inode-number path, which will follow `i_file_acl`. Tier 2.
- `ext2fs_xattr_get(h, key, &value, &len)` — fetch by name, e.g. `trusted.lma`.

**Answered 2026-08-17 — `ext2fs_xattrs_read_inode()` does follow `i_file_acl`.**
Measured, not read out of the source: `tests/mkimage.sh` now builds `widelov1`,
a 60-stripe file whose `trusted.lov` is 1472 bytes and therefore cannot fit a
1024-byte inode (`debugfs` confirms `File ACL: <block>`), and all 60 stripes
come back from the first `read_inode()` pass. e2fsprogs 1.47.0.

Both halves of the prediction above turn out to matter, in opposite directions:

- **Correctness is free.** No hand-rolled inline parser, no second call: every
  tier-1 predicate is answerable on every object, spilled or not. The
  `ext2fs_xattrs_read()` retry in `lfu_read_xattrs()` is therefore dead code on
  this libext2fs and kept only as insurance for builds that behave otherwise.
- **The cost is invisible.** The extra block read happens *inside* libext2fs,
  so a caller cannot count it, and the inline-only request the tier separation
  wanted does not exist in the API. What is countable is the condition: an
  object with `i_file_acl != 0` under a filter that demands a tier-1 xattr has
  necessarily paid for the block. That is what the `tier-2 (read)` line in the
  summary reports, and it is a *predicate-and-data* property, not a per-object
  measurement of I/O.

So tier 1 → tier 2 is not a code boundary here at all; it is a cost boundary
that has to be inferred. If the tier-2 rate on a real filesystem ever turns out
to matter (§7 of `filter-levels.md`), measuring it properly means timing the
scan with and without a tier-1 predicate, not counting fallbacks.

---

## 7. Filter pushdown and evaluation order

Filters (`architecture.md` §4) are evaluated **at the source** so non-matching
objects never enter the stream. Within this module, the rule is:

> Evaluate predicates in ascending cost tier. Reject as early as possible. Never
> perform a tier-2 read for an object already rejected by a tier-0 predicate.

For the LUG slide 21 example —
`lfs find /lfs02 -atime +30d -blocks +1G -projid 1999` — ~~all three predicates
are tier 0~~. Every object is decided from the inode buffer alone, and only
survivors cost a tier-1 LMA parse. That is the intended fast path, and it is why
the example was chosen.

> **Corrected 2026-08-16.** Two of the three are tier 0; `-blocks +1G` is tier 1
> via `trusted.som`, per the §6 correction above. The example is still the right
> fast-path illustration — the two tier-0 predicates reject nearly everything
> before any xattr work — but as implemented today `blocks_gt` compares
> `i_blocks`, so against a real MDT with striped files it would match nothing.
> `tests/run_tests.sh:78` exercises `--blocks` only against a synthetic image
> with no striped files, and the §17 `lfs find` oracle compared FID *sets*, not
> attribute predicates, so this is unexercised rather than known-good. One run
> against the benchfs MDT settles it.

Consequences for the filter compiler:

- The filter program must expose each predicate's **tier** so the module can sort
  them. A filter API that presents an opaque match function forfeits this
  entirely — worth stating in the Filter Rule module design.
- Predicates on the same tier should be ordered by selectivity where known.
- An xattr regexp filter (LUG slide 20) is tier 1 or 2 depending on inline fit,
  and must be ordered last.
- Predicates the module cannot evaluate are returned as **residue** for the
  caller to apply, and the module must report which, so `liblfu` can apply them
  transparently and consumers see one filter.

---

## 8. Consistency model

### 8.1 Staleness — accepted, and correctly so

On-disk metadata lags in-memory state by up to tens of seconds, affecting only
objects created/modified/removed shortly before being scanned. The HLD accepts
this: a scan is not atomic with respect to concurrent modification, a snapshot
would not help (it merely misses recent changes instead), and target consumers
care about aggregates and bulk lists where a few objects do not change the
answer.

This design does not revisit that conclusion. It is right for the intended
consumers.

### 8.2 Torn reads — the real risk (`open-questions.md` *Torn metadata on a live device*)

Staleness is not the only failure mode of reading a live read-write device.
Blocks can be read while being written, and structures can be observed mutually
inconsistent. The HLD does not discuss this.

#### Checksums may make this a solved problem — or not

libext2fs exposes `ext2fs_inode_csum_verify()`,
`ext2fs_ext_attr_block_csum_verify()`, `ext2fs_inode_bitmap_csum_verify()` and
`ext2fs_group_desc_csum_verify()`. **If `metadata_csum` is enabled, a torn read
is detected exactly rather than heuristically** — which would turn the whole of
*Torn metadata on a live device* from a research question into a retry loop.

The catch: `mkfs.lustre` appends **`uninit_bg`** (`libmount_utils_ldiskfs.c:632`),
which is the older `GDT_CSUM` feature — it checksums *group descriptors only,
not inodes*. `metadata_csum` does not appear anywhere in `mkfs.lustre`. Whether
a real MDT has inode checksums therefore depends on `mke2fs.conf` defaults in
the e2fsprogs build being used, and modern upstream mke2fs does enable
`metadata_csum` by default.

**This is worth checking first, on a real target (`dumpe2fs -h`), because the
answer changes the design:**

- `metadata_csum` on → verify each inode's checksum, retry on failure, and the
  heuristics below become a secondary net.
- `metadata_csum` off → heuristic validation is all we have, and the skip-rate
  measurement (*Torn-read rate*) becomes correspondingly more important.

#### Measured on a live MDT under load

Under sustained metadata churn (bulk `mkdir`/create/`rm -rf` from a client),
repeated scans of the mounted MDT showed **up to ~50% of allocated inodes in an
inconsistent on-disk state** — 880 of ~1740 in the worst sample. Every one had
the same signature:

```
mode=0100644  nlink=0  extra_isize=32  dtime=0
```

That is not a zeroed or deleted inode. It is a **valid mode with `nlink=0` and no
deletion time** — an inode whose table block was written after allocation but
before the directory entry that would raise its link count was committed. Under
a create-heavy workload this state is common, not exceptional.

All were caught and skipped by the validation below; the count decayed to zero
within ~45s of the load stopping, and a quiescent scan reports `validate=0`.

**This qualifies the HLD's consistency argument.** The HLD states the affected
objects "would represent only a tiny fraction of objects". For a long scan of a
mostly-static filesystem that holds. For a filesystem under an ingest burst it
does not — the affected set is most of the recently-created objects, which is
often exactly the set a consumer cares about.

> **Update 2026-08-06 — reframed after review (Andreas).** The inconsistency is
> bounded by the journal commit interval: it affects only inodes created within
> the ~5–10 s before their table blocks are checkpointed to the filesystem
> proper. Our own decay observation (~45 s to `validate=0` after load stops)
> matches that mechanism. The ~50% figure is therefore the rate *within a toy
> namespace whose entire population sat inside the commit window* — on a
> filesystem with 10⁸–10⁹ files the same window holds a tiny fraction of the
> total, and the HLD's characterisation stands. Two further points from that
> review:
>
> - **Begin-to-end scan skew dominates per-object staleness anyway.** Even a
>   perfectly consistent reader gives results skewed by the scan duration
>   (inodes M..N skipped as unused, then allocated moments later). At 1M obj/s
>   a 10⁹-file scan takes ~17 min; a 5–10 s per-object lag is noise inside
>   that. This applies equally to the OSD scanner and erodes its "in-memory,
>   current" advantage.
> - **The designed mitigation is the Changelog Input Scanner** — an independent
>   pipeline module that notifies consumers of updates the scan raced with. A
>   consumer that wants *recent* files should be fed from the changelog, not
>   from a full scan; the "affected set is what the consumer wants" concern
>   above is properly answered by that split, not by hardening this scanner.
>
> What the review does **not** dissolve is the second consequence below: the
> undetectable mid-update emission. It is bounded by the same commit window
> (so also a tiny fraction), but it is *uncounted* rather than
> skipped-and-counted — a stated assumption, exactly closable by
> `metadata_csum`, and incidentally mitigated by a changelog overlay flagging
> recently-modified FIDs as suspect.

Two consequences worth carrying forward:

- **Skip-counting is not optional.** Reporting "515 emitted, 880 skipped" is
  honest; silently dropping 880 would present a half-complete namespace as
  complete, which is the failure mode that does real damage to a consumer that
  deletes or migrates things.
- **The inverse case is undetectable without checksums.** An inode observed
  mid-update with `nlink` already plausible but other fields stale *passes*
  validation and is emitted with wrong attributes. Nothing here catches that.
  With `metadata_csum` it would be caught exactly — and the target survey found it **off**
  on a real MDT (§17). This is the strongest argument for enabling it.

Note also that `nlink=0` with a valid mode is *also* the signature of a genuine
**orphan** (unlinked but still open, holding space). The heuristic conflates the
two. Consumers that care about space accounting may want orphans reported rather
than skipped.

Mitigations, in order of value:

1. **Read as little as possible.** §4.1 — inode bitmap, inode table, and EA
   blocks only. No block bitmaps, no extent trees, no directory blocks, no
   journal. This is also `e2scan`'s answer.
2. **Validate every inode before trusting it.** Cross-check `i_links_count > 0`,
   `i_mode` a legal type, `i_extra_isize` within the inode size, and the inline
   xattr magic. A struct that fails validation is counted and skipped, never
   interpreted.
3. **The allocation bitmap is the authority on existence.** `ext2fs_open_inode_scan()`
   walks the inode *table* and returns freed inodes too — their contents are
   stale but perfectly parseable. `ext2fs_read_inode_bitmap()` +
   `ext2fs_test_inode_bitmap2()` is mandatory, exactly as `osd_iit_next()`
   consults the bitmap in the kernel. Also check `i_dtime != 0` for inodes freed
   since the bitmap block was written.

   *Found by testing:* without the bitmap check, 31 deleted directories were
   reaching the validation heuristics and being rejected there by accident. The
   heuristics were silently doing the bitmap's job, less reliably.

   A bit *set* for an inode that fails validation is a skip, not an error.
4. **Never trust a length field without bounding it.** Every xattr length,
   `leh_len` in `struct link_ea_header` (`lustre_idl.h:3493`), and every
   `lee_reclen` in `struct link_ea_entry` must be bounds-checked against the
   containing buffer before use. This is the parser's most exposed surface —
   see §12.
5. **Re-read on ambiguity**, once, at group granularity. A torn read is
   transient; a genuinely corrupt structure is not. One retry cheaply
   distinguishes them.
6. **Count and report.** A scan reporting *N objects, M skipped as
   unparseable* is honest. A scan silently dropping M is not, and would present
   an incomplete namespace as a complete one — which is the failure mode most
   likely to cause real damage in a consumer that deletes things.

**Validation needed before this is settled:** a scan against a live,
write-heavy filesystem with the skip counter watched, plus the same scan against
an idle filesystem for comparison. The lab cluster can do this. Until then,
"tolerable torn-read rate" is an assumption, not a result.

### 8.3 Not reading the journal

An ldiskfs device with an unreplayed journal has metadata that is stale in a
*structured* way. The scanner does not replay it (that would require write
access) and does not read it. On a cleanly-mounted live target this is
immaterial. On a device that was not cleanly unmounted, the scan may reflect
pre-crash state — the scanner should detect the "needs recovery" superblock state
and **report it prominently** rather than scan silently.

---

## 9. Parallelism, checkpoint and restart

### 9.1 Unit of work: the block group

The kernel's OI scrub iterates exactly this way — `osd_iit_next()`
(`osd_scrub.c:518`) walks the per-group inode bitmap with
`ldiskfs_find_next_bit()` over `LDISKFS_INODES_PER_GROUP`, carrying
`struct osd_iit_param { sb, bitmap, bg, gbase, offset, start }`
(`osd_scrub.h:27`). The userspace scanner mirrors it.

The block group is the right unit because it is the natural locality unit: one
bitmap read plus a contiguous inode table run, both already adjacent on disk.
Threads claim groups from a shared atomic counter — no partitioning decision, and
natural load balancing when groups differ in occupancy.

libext2fs supports this directly: **`ext2fs_inode_scan_goto_blockgroup(scan,
group)`** positions a scan at a group boundary, so each thread runs its own
`ext2_inode_scan` over its claimed groups. The same call is what makes
checkpoint/restart (§9.2) trivial.

**Threading model — needs a decision.** libext2fs 1.47 has explicit thread
support (`EXT2_FLAG_THREADS`, `CHANNEL_FLAGS_THREADS`, `IO_FLAG_THREADS`,
`ext2fs_rw_bitmaps(fs, flags, num_threads)`), added for parallel `e2fsck` — and
note that **parallel e2fsck pass2/3 (LU-14679) is on the 2.19 roadmap**, the same
release as LFU, so this path is actively being exercised by others.

Two options, in order of preference:

1. **One `ext2_filsys` per thread**, each opening the device independently,
   read-only. Trivially safe, costs one file descriptor and one superblock parse
   per thread, and sidesteps every question about which parts of `ext2_filsys`
   are shared mutable state. Recommended for v1.
2. **A shared `ext2_filsys` with `EXT2_FLAG_THREADS`.** Fewer resources, but
   requires knowing precisely what that flag does and does not protect.

Start with (1). It is boring, obviously correct, and the resource cost is
negligible next to a multi-MiB read buffer per thread.

**Open flags** for the target: `EXT2_FLAG_SKIP_MMP` (mandatory — MMP is enabled
on Lustre targets, §4.2b), `EXT2_FLAG_64BITS`, `EXT2_FLAG_SOFTSUPP_FEATURES`
(tolerate feature flags a given libext2fs build doesn't fully implement), and
**never `EXT2_FLAG_RW`**. Consider `EXT2_FLAG_DIRECT_IO`: on a live MDS, pulling
the entire inode table through the page cache would evict the MDS's own working
set, which is a real production concern independent of scan throughput.

- Inode table reads within a group are **large and sequential** (multi-MiB), the
  access pattern the 1 GiB/s assumption requires.
- Tier-2 EA-block reads are random and are what break it (§6).
- Thread count should track device queue depth, not core count. For NVMe, enough
  threads to keep the queue full; for HDD-backed MDTs, fewer, since seeking
  between groups destroys the sequential pattern.
- `bg_itable_unused` in the group descriptor allows skipping the tail of a
  group's inode table entirely — a large win on freshly-formatted or sparse
  filesystems, and free to use.

### 9.2 Checkpoint

Scan position is `(block group, inode offset)` — the same coordinate the kernel
checkpoints. Because groups are claimed independently and complete out of order,
a checkpoint is *the set of completed groups plus in-flight positions*, not a
single watermark.

Simplest correct form: a bitmap of completed groups, written periodically.
Restart re-runs any group not marked complete. This over-scans by at most one
group per thread, needs no ordering guarantees, and is a few KiB for any real
filesystem.

**Restart is not resumption of a consistent scan** — the filesystem has moved on.
A restarted scan is a new fuzzy snapshot that happens to skip work already done.
Consumers requiring a coherent view must not rely on checkpoint/restart, and the
stream should carry a flag marking a resumed scan (`open-questions.md` *Restart, checkpoint and scan identity*).

### 9.3 Rate limiting

Scanning at device bandwidth on a live MDT competes directly with the MDS.
Needs an explicit throttle — IOPS or bandwidth ceiling, or a duty cycle. The
"1 hour for 4 billion objects" figure is an unthrottled ceiling; a production
scan on a live target should be expected to run slower by design.

---

## 10. Interactions

### 10.1 LFSCK and OI scrub (`open-questions.md` *LFSCK and OI Scrub coordination*)

No interlock exists, and none is possible without server coordination — this
module does not talk to the MDS. Both may run concurrently, competing for device
bandwidth. This is an argument for §9.3 throttling and a point to raise: an
unthrottled LFU scan can meaningfully slow a running LFSCK.

### 10.2 Wide striping

Filesystems formatted for >59 stripes use 512 B inodes and external EA blocks
(§4.3), making layout access tier 2 for effectively every object. Layout-filtered
scans on such filesystems will not approach the performance target. The scanner
should detect this at open (inode size vs. feature flags) and **warn**, rather
than silently underperform.

### 10.3 LMR (`open-questions.md` *LMR duplicate objects*)

With Lustre Metadata Redundancy (2.19+), a mirrored inode exists on multiple
MDTs, so a per-target scan enumerates it once per replica and the merged stream
contains duplicate FIDs. This module cannot deduplicate — it sees one device and
has no cross-target view.

What it **can** do, and should:

- emit a per-record **replica hint** if LMA gains a flag identifying replica vs.
  primary, and
- always emit the source target id, so the merge module can deduplicate on
  `(FID)` and pick a winner deterministically.

The source target id is cheap and useful regardless, so it is in the record
contract (§2.2) now. Whether the replica distinction is representable is a
question for the LMR design, and is why *LMR duplicate objects* needs answering before the record
layout freezes.

### 10.4 Encryption

`LMAI_ENCRYPT` marks encrypted inodes. Their **filenames in linkea are
ciphertext**, and the scanner has no keys and should never have any. Encrypted
objects must be emitted with a clear flag so that consumers and Output Format
modules do not present ciphertext names as pathnames. Any filter matching on
names is meaningless for these objects and must be treated as residue, not
silently evaluated against ciphertext.

---

## 11. Performance model and validation

### 11.1 The arithmetic

Target: 1M objects/sec/MDT at ≥1 GiB/s ⇒ ~1 KiB/object — exactly one default MDT
inode (§4.3). The target is therefore *achievable but has no headroom*: it
assumes one sequential inode read per object and nothing else.

| Factor | Effect |
|---|---|
| Default 1 KiB inode, tier 0/1 only | at target |
| Sparse groups (`bg_itable_unused`) | better than target |
| Tier-2 EA block reads | one random read per hit — dominant cost when frequent |
| 512 B inodes (wide striping) | 2× objects per byte, but layouts all become tier 2 |
| 2048 B inodes | half the objects per byte read |
| Encrypted/long filenames | larger linkea, more tier-2 |

### 11.2 What to measure, in order

1. Objects/sec and bytes/sec on an idle MDT, tier 0/1 only — the ceiling.
2. **Tier-2 hit rate** across realistic filesystems — the single number
   determining whether real filters meet the target.
3. Same scan on a live write-heavy target: throughput, and the §8.2 skip counter.
4. Scaling vs. thread count on NVMe and on HDD-backed MDTs.
5. End-to-end vs. `lfs find` for the slide-21 query — the number that justifies
   the project.

The lab cluster (`../lab`, MDT on `/dev/vdb`) is enough for correctness and for
1, 3, 4. Item 2 needs a realistic namespace, and item 5 needs scale.

---

## 12. Security posture of the parser

The scanner parses **untrusted on-disk data** — potentially torn, potentially
corrupt, potentially crafted if any user has ever controlled xattr content —
in userspace, at high privilege (block device read). The parsing surface is
`trusted.link` (variable-length records with embedded lengths), `trusted.lov`
(variable components), and the inline xattr region.

- Every length and offset bounds-checked against its containing buffer before
  use (§8.2 item 4).
- The scanner should be fuzz-tested against malformed inode and xattr buffers.
  This is cheap: the parser is a pure function from a byte buffer to a record,
  so it can be fuzzed in isolation without a filesystem at all.
- Consider a `--paranoid` mode that treats any validation failure as fatal, for
  use when scan output feeds a destructive consumer (trash purge, HSM release).

---

## 13. Testing

Mapping to the HLD's regression list, plus what this module needs specifically.

| Test | Method |
|---|---|
| Full reporting of MDT objects | Scan vs. `lfs find` enumeration of the same target; sets must match |
| Full reporting of OST objects | Scan vs. OST object count |
| Internal objects excluded | Assert no OI/quota/llog/`O` FIDs in output |
| FID correctness | Sample FIDs → `lfs fid2path` resolves |
| IGIF handling | Requires a pre-2.0 upgraded image, or a synthetic one |
| Classification ladder | Unit tests per branch of §5 against synthetic inodes |
| Tier-2 path | Force wide striping / many hardlinks; assert layout and linkea still correct |
| Torn reads | Live write-heavy scan; skip counter; compare against idle scan |
| Restart | Kill mid-scan, resume, assert no missing objects (duplicates allowed) |
| Parallel correctness | Vary thread count; output set must be identical |
| Filter pushdown | Same predicate as filter vs. post-filter; identical results |
| Filter ordering | Assert no tier-2 read for tier-0-rejected objects |
| Parser robustness | Fuzz inode/xattr buffers (§12) |
| Unclean device | Scan a device needing recovery; assert warning is raised |

The `lfs find` cross-check is the primary correctness oracle and should be built
first — everything else is easier once the two enumerations can be diffed.

---

## 14. Dependencies and packaging

- **libext2fs** (e2fsprogs). Not currently a Lustre userspace build dependency.
  **Verified present in stock upstream 1.47.0** (Ubuntu 24.04 `libext2fs-dev`,
  headers inspected):

  | Needed | Status |
  |---|---|
  | `ext2fs_open_inode_scan`, `ext2fs_get_next_inode_full` | present |
  | `ext2fs_inode_scan_goto_blockgroup` | present — enables §9 group parallelism |
  | `ext2fs_xattrs_open/read/read_inode/get/iterate/count` | present — full API |
  | `ext2fs_inode_csum_verify` and friends | present — see §8.2 |
  | `EXT2_FLAG_THREADS`, `IO_FLAG_THREADS` | present |
  | `EXT2_FLAG_SKIP_MMP`, `EXT2_FLAG_SOFTSUPP_FEATURES`, `EXT2_FLAG_DIRECT_IO` | present |
  | `EXT4_FEATURE_INCOMPAT_DIRDATA` | defined — **but unusable, see below** |

  **The API surface is entirely available upstream. Opening a real MDT is not.**

  Stock libext2fs defines `EXT4_FEATURE_INCOMPAT_DIRDATA` (0x1000) in
  `ext2_fs.h`, but omits it from `EXT2_LIB_FEATURE_INCOMPAT_SUPP`
  (`ext2fs.h:646-659`), so `ext2fs_open()` rejects any filesystem carrying it.
  `EXT2_FLAG_SOFTSUPP_FEATURES` does not rescue this: **`EXT2_LIB_SOFTSUPP_INCOMPAT`
  is `(0)`** (`ext2fs.h:680`) — the soft-support escape hatch is empty for
  incompat features. Stock `mke2fs` likewise refuses to *create* dirdata.

  Verified experimentally by `tests/dirdata_probe.sh`, which sets the bit
  directly in the superblock and attempts to open:

  ```
  s_feature_incompat: 0x6c2 -> 0x16c2
  stock dumpe2fs                        : REFUSES
  lfind-ldiskfs (SOFTSUPP set)       : REFUSES
  ```

  Since `mkfs.lustre` sets `dirdata` on every MDT, **the WhamCloud e2fsprogs fork
  is a hard requirement.** This is why `e2scan` lives there.

  **The cost of that dependency is zero in practice.** Lustre already requires
  it: `lustre.spec.in:354` has `BuildRequires: e2fsprogs-devel >= 1.47.3-wc1`,
  and every ldiskfs server installs the `lustre-e2fsprogs` repo as a
  prerequisite (`notes/reference/build_install.md:16`). We are adopting a
  dependency the target systems already carry.

  Worth proposing separately: adding `DIRDATA` to upstream's
  `EXT2_LIB_FEATURE_INCOMPAT_SUPP`. It does not change inode read semantics, so
  a read-only consumer is safe with it. That would let the scanner build against
  stock e2fsprogs on non-Lustre systems — useful for CI and for offline analysis
  of MDT images. Not a dependency, just a nice-to-have.
- No new kernel dependency. No Lustre kernel module required at runtime.
- Lustre UAPI headers for LMA/FID/linkea definitions — already installed by
  `lustre-devel`; the on-disk structures must not be redefined locally.

---

## 15. Open questions specific to this module

| Topic | Question | Status | Blocks |
|---|---|---|---|
| **Filter cost tiers** | Can the filter API expose per-predicate cost tiers (§7)? | open — needs the Filter Rule module owner | Whether pushdown ordering is possible at all |
| **Internal-object exclusion** | **How to exclude internal objects LMA cannot identify (§5.1b)?** | open here — inode-number denylist from a one-time root directory read; **filed upstream as LU-20602** for the durable fix | Correctness of "visible"; 3 objects leak today |
| **Should metadata_csum be on?** | **Should `metadata_csum` be enabled on Lustre MDTs?** It is off today (§17) and is the only exact torn-read detector | open — a question for Andreas; affects `mkfs.lustre` defaults | Whether §8.2 stays heuristic forever |
| **xattr API depth** | Does `ext2fs_xattrs_read_inode()` follow `i_file_acl`, or is it inline-only? (§6.1) | **answered 2026-08-17: it follows.** Tier 1 is free and correct for spilled xattrs; there is no inline-only request, so tier-2 *cost* can only be inferred, not counted | Tier 1 needs no hand-rolled parser; the tier-2 rate needs timing, not a counter |
| **Replica vs primary flag** | Is there an LMA/LMR flag distinguishing replica from primary (*LMR duplicate objects*)? | open | Record layout, dedup correctness |
| **Throttling policy** | Throttling policy for scans on live targets (§9.3) | open | Production usability |
| **Flag resumed scans** | Should a resumed scan be flagged in the stream (*Restart, checkpoint and scan identity*)? | open | Consumer semantics |
| **Paranoid mode** | Is `--paranoid` (validation failure = fatal) required for destructive consumers? | open | Consumer safety |
| **Orphan reporting** | Should genuine orphans (nlink=0, still open) be reported rather than skipped? (§8.2) | open | Space-accounting consumers |
| **Torn-read rate** | Torn-read/skip rate on a live target (*Torn metadata on a live device*) | **resolved — measured at scale**: 0.05% worst case (5,979 of 12M) under sustained creates, all detected and counted; 0 when quiescent. The earlier ~50% figure was a 1,740-inode namespace entirely inside the journal commit window (§8.2, §17) | — |
| **libext2fs API availability** | Does the required libext2fs API exist, and can it open a real MDT? | **resolved** — API yes on stock; **opening an MDT needs the WhamCloud fork**, which Lustre already requires (§14) | — |
| **Is metadata_csum on?** | Is `metadata_csum` enabled on real MDTs? | **resolved — no** (§17). Only `uninit_bg`. Heuristics are the only defence | — |

**Next actions.** *Internal-object exclusion* is implementable now and is the last known correctness gap.
*Filter cost tiers* and *Should metadata_csum be on?* are conversations, not experiments. *xattr API depth* is a source read.

## 16. Prototype status

`src/lfu_scan_ldiskfs.c` — single-threaded, builds clean, 17/17 tests passing
against a synthetic MDT-like image (`tests/mkimage.sh`, `tests/run_tests.sh`).

**Implemented:** device open with the §9.1 flag set · inode scan · tier-0
attribute extraction · tier-1 LMA read and byte-swap · the §5 classification
ladder · §7 tier-0 filter with cost-ordered evaluation · §8.2 validation and
skip-counting · tier-2 hit-rate reporting · the §4.2b/§8.2/§10.2 open-time
warnings.

**Not yet:** parallel scan over block groups (§9.1) · checkpoint/restart (§9.2) ·
rate limiting (§9.3) · linkea and layout parsing (tier 1/2) · the real Object
Stream encoding — output is text · OST-side specifics (§5.1).

**Validated by the prototype, not just asserted:**

- The classification ladder reproduces `osd_scrub_get_fid()` on synthetic
  objects covering every branch.
- Tier-0 filters reject before any xattr parse — the test asserts 17 of 18
  objects are filtered before classification when only one matches.
- `LMAI_RELEASED` is vestigial (§5) — the prototype caught this document
  asserting the opposite.
- The `dirdata` dependency above.

## 17. Results on a real MDT

Run 2026-08-05 against the lab cluster (`cluster_setup.md`): `testfs-MDT0000` on
`/dev/vdb`, RHEL 9.7, Lustre 2.17, MDT mounted and serving a client throughout.
Built on the MDS against **e2fsprogs-devel-1.47.3-wc2** with no source changes.

### Target configuration — every §4 prediction confirmed

```
Filesystem features: has_journal ext_attr resize_inode dir_index filetype extent
                     flex_bg ea_inode dirdata large_dir sparse_super large_file
                     huge_file uninit_bg dir_nlink quota project
Inode size:          1024
```

| Prediction | Result |
|---|---|
| §4.3 — MDT inodes are 1024 B so Lustre xattrs fit inline | **1024 B confirmed.** Measured tier-2 rate: **0.0%** — every LMA read was free |
| §4.2b — `ea_inode` enabled on MDTs | confirmed |
| §4.2b — `dirdata` set, so stock libext2fs cannot open | confirmed; the fork's `EXT2_LIB_FEATURE_INCOMPAT_SUPP` includes `EXT4_FEATURE_INCOMPAT_DIRDATA`, stock's does not |
| §8.2 (*Is metadata_csum on?*) — is `metadata_csum` on? | **No.** Only `uninit_bg` (group descriptors). No inode checksums exist to verify |
| §4.2b — `mmp` enabled | **not** set on this target; `SKIP_MMP` is harmless but was not needed |

### Correctness — the `lfs find` oracle (§13)

Scanner FID set vs. `lfs find` + `lfs path2fid` from the client:

| Namespace size | Client FIDs | Scanner FIDs | **Misses** | Extras |
|---|---|---|---|---|
| small | 173 | 179 | **0** | 6 |
| after churn | 509 | 515 | **0** | 6 |

**Zero misses at both scales** — the property that matters, since a namespace
scanner that loses objects is dangerous. Extras stayed at exactly 6 while the
namespace tripled: 3 are `.lustre` pseudo-directories (correctly visible, merely
hidden from `lfs find`) and 3 are the internal objects of §5.1b.

### Live-write behaviour (*Torn-read rate*)

See §8.2 for the full result: up to ~50% of allocated inodes in an inconsistent
state under create-heavy load, all detected and skipped, decaying to zero within
~45s of the load stopping.

### Not measured

**Throughput.** The lab MDT holds 100 000 inodes with ~1 800 in use; the whole
inode table fits in page cache, so the observed ~1–3 M inodes/sec is a
cache-hit figure and says nothing about the 1 M objects/sec/MDT target. That
number needs a realistically-populated MDT on real storage.

---

## References

Verified against `../lustre-release` @ `v2_17_55-2-gd717692511`:

- `include/uapi/linux/lustre/lustre_user.h:460-534` — LMA, `lustre_ost_attrs`, LMAC/LMAI flags
- `include/uapi/linux/lustre/lustre_idl.h:278-310` — FID sequence ranges
- `include/uapi/linux/lustre/lustre_idl.h:1283-1292` — xattr names
- `include/uapi/linux/lustre/lustre_idl.h:3493-3508` — `link_ea_header`, `link_ea_entry`
- `lustre/osd-ldiskfs/osd_scrub.c:518` — `osd_iit_next()`, bitmap iteration
- `lustre/osd-ldiskfs/osd_scrub.c:576` — `osd_scrub_get_fid()`, classification ladder
- `lustre/osd-ldiskfs/osd_scrub.h:27` — `struct osd_iit_param`
- `lustre/osd-ldiskfs/osd_handler.c:460` — `osd_get_lma()`, swab and incompat check
- `lustre/osd-ldiskfs/osd_oi.c:49` — `OSD_OI_NAME_BASE`
- `lustre/utils/libmount_utils_ldiskfs.c:628-700` — MDT feature flags (`mmp`, `ea_inode`, `dirdata`, `uninit_bg`, `^fast_commit`)
- `lustre/utils/libmount_utils_ldiskfs.c:883-890` — MDT inode sizing
- `lustre/utils/lfs.c:7117` — `lfs find -blocks`

libext2fs 1.47.0 headers (`ext2fs.h`, `ext2_fs.h`), inspected from the Ubuntu
24.04 `libext2fs-dev` package without installing it:

- `ext2fs.h:1296-1331` — xattr API
- `ext2fs.h:1565-1585` — inode scan API
- `ext2fs.h:1082-1134` — checksum verification API
- `ext2fs.h:195-222` — open flags
- `ext2_fs.h:867` — `EXT4_FEATURE_INCOMPAT_DIRDATA`

External: e2scan (WhamCloud e2fsprogs) · Lester (`github.com/ORNL-TechInt/lester`)
· LFSCK Phase 1 OI Scrub architecture (wiki.lustre.org).
