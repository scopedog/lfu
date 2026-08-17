# LFU ZFS Device Input Scanner — Detailed Design (sketch)

**Module:** `lfu_input_zfs` — the ZFS-backend counterpart to the ldiskfs device
scanner.
**Parent architecture:** [`architecture.md`](architecture.md) §6.
**Siblings:** [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) (the
first-wave scanner, prototyped) · [`design-osd-scanner.md`](design-osd-scanner.md)
(the in-kernel OSD API scanner).
**Status:** v0.2 — **prototype built and passing** (`src/lfu_scan_zfs.c`,
`make zfs`, 16/16 tests; §14). Route 1 is proven end-to-end against a synthetic
dataset. The remaining unverified facts (§4.4 on a *real* osd-zfs MDT, and the
§12 registry/version questions) are narrower than at v0.1 but still gate
production claims.

Code references are to `../lustre-release` @ `v2_17_55-2-gd717692511`. Items
marked **[verified]** were read in that tree; everything else is design
proposal.

---

## 1. Purpose and scope

Produce an Object Stream from a Lustre-on-ZFS MDT or OST by reading the dataset
directly from userspace, without going through a mounted Lustre server.

### Why this exists

`design-ldiskfs-scanner.md` covers ldiskfs only. Roughly the same job on ZFS
needs different machinery, and the OSD API scanner — the other route to ZFS —
is second-wave work gated on a 6.7× throughput gap
([`throughput-results-2026-08-06.md`](throughput-results-2026-08-06.md)). A
userspace ZFS scanner is not a substitute for the OSD path; it serves the cases
the OSD path structurally cannot: **exported or unmounted pools, snapshots,
servers with no LFU kernel support, and analysis on a different machine
entirely.**

### A correction worth recording

An earlier revision of `architecture.md` argued ZFS should be served *only* by
the OSD API scanner, on the grounds that ZFS has no inode-table analogue to scan
sequentially. **That is wrong, and the tree says so:** osd-zfs's own object-table
iterator is `dmu_object_next()` over the objset (`osd-zfs/osd_scrub.c:1672`
**[verified]**) — a sequential walk of the dnode array in object-ID order,
structurally the same thing as `ext2fs_get_next_inode()`.

What that earlier argument got right was narrower and still holds: **zester's
approach is not viable.** It shells out to `zdb -dddd` and parses text dumps
(Python 2, Lustre 2.8 / ZFS 0.6.5 era, regular files only, no DNE, known to
over-report sizes). Read it for its MDT↔OST join logic and its
size-reconstruction traps — not as an implementation base.

### In scope

- MDT and OST datasets of a Lustre-on-ZFS filesystem.
- Read-only. Never writes to the pool.
- Snapshot-based scanning as the **default** operating mode (§8).

### Out of scope

- Repair of any kind. This is not `zdb -c`, not scrub, not LFSCK.
- Pathname resolution (an Output Format concern, priced separately).
- Encrypted datasets whose keys are not loaded — a raw send/read yields
  ciphertext and the scanner must detect and refuse this rather than emit
  garbage (§15).

---

## 2. Interface contract

Identical to the ldiskfs scanner by design — see `design-ldiskfs-scanner.md` §2.
The emitted record, the attribute mask, the filter program and the control
surface are all shared. **The only thing that differs is where the bytes come
from.** That is the whole architectural point of §3.

---

## 3. Operating model: one binary, two backends

The ldiskfs prototype's structure holds above the device layer. Everything in
these areas transfers unchanged:

| Transfers from the ldiskfs scanner | Where |
|---|---|
| Object classification ladder | `design-ldiskfs-scanner.md` §5 |
| Attribute cost tiers | §6 |
| Cost-ordered filter pushdown | §7 |
| Record contents / Object Stream encoding | §2.2 |
| Skip and gap accounting | §8.2 |
| `lfs find` + `lfs path2fid` correctness oracle | §13 |
| Parser bounds-checking discipline | §12 |

The backend-specific surface is narrow — essentially one iterator:

```c
/* Target backend interface. Two implementations: ldiskfs, zfs. */
struct lfu_target_ops {
        int  (*open)(struct lfu_target *, const char *spec, int flags);
        int  (*next)(struct lfu_target *, struct lfu_raw_obj *);  /* id + attrs + xattr blob */
        void (*close)(struct lfu_target *);
};
```

**Recommendation: extend the existing scanner binary with this interface
rather than writing a separate `lfind-zfs`.** The filter, output and
correctness machinery is the bulk of the work and should be written once. The
ZFS backend's whole job is "give me `(object id, attributes, LMA)`".

---

## 4. On-disk structures consumed

### 4.1 Object enumeration **[verified]**

`dmu_object_next(os, &oid, B_FALSE, 0)` advances to the next allocated dnode in
object-ID order, returning `ESRCH` at the end (`osd_scrub.c:1672-1680`). This is
the ZFS analogue of the inode-bitmap-gated inode-table walk, with one important
difference: **allocation is implicit.** There is no separate bitmap to
cross-check against, because `dmu_object_next()` only returns allocated dnodes.
The ldiskfs scanner's "the bitmap is the authority on existence" rule
(`design-ldiskfs-scanner.md` §8.2 mitigation 3) has no counterpart here and
needs no counterpart.

### 4.2 Attributes: the SA bonus buffer **[verified]**

Lustre stores object attributes as ZFS System Attributes in the dnode's bonus
buffer, reusing the ZPL attribute set (`osd-zfs/osd_object.c:188-248`):

| Attribute | SA slot |
|---|---|
| mode, size, links, generation | `SA_ZPL_MODE`, `SA_ZPL_SIZE`, `SA_ZPL_LINKS`, `SA_ZPL_GEN` |
| uid, gid, projid | `SA_ZPL_UID`, `SA_ZPL_GID`, `SA_ZPL_PROJID` |
| atime, mtime, ctime, crtime | `SA_ZPL_ATIME`, … |
| rdev, flags, parent | `SA_ZPL_RDEV`, `SA_ZPL_FLAGS`, `SA_ZPL_PARENT` |

**SA slot numbers are per-dataset, not constants.** osd-zfs resolves them at
mount by reading the SA registry: `zap_lookup(od_os, MASTER_NODE_OBJ,
ZFS_SA_ATTRS, …)` then `sa_setup(..., zfs_attr_table, ZPL_END, &z_attr_table)`
(`osd_handler.c:981-988` **[verified]**). **The scanner must replicate this
lookup — it may not assume fixed offsets.** This is the single most likely
source of silent wrong-attribute bugs, and §13 requires a test for it.

### 4.3 Lustre xattrs: one packed nvlist **[verified]**

`trusted.lma`, LOV and linkea live in the **`SA_ZPL_DXATTR`** attribute as an
XDR-packed nvlist (`osd_xattr.c:47-70`). The read path is:

```
dnode bonus → sa_lookup(SA_ZPL_DXATTR) → nvlist_unpack()
            → nvlist_lookup_byte_array(nvbuf, XATTR_NAME_LMA, &lma, &size)
            → lustre_lma_swab(lma) → lma->lma_self_fid
```

exactly as `osd_scrub.c:400-407` does **[verified]**. Note this is *one* unpack
per object yielding *all* Lustre xattrs at once — structurally cheaper than
ldiskfs, where inline and external EA blocks are separate reads.

Objects whose DXATTR lookup returns `ENOENT`/`ENODATA` have no Lustre identity;
the scrub path skips them (`goto again`, `osd_scrub.c:395`). See §6.

### 4.4 Why the attributes should be cheap — dnode sizing **[unverified, load-bearing]**

`mkfs.lustre` sets **`dnodesize=auto`** on ZFS targets (and `recordsize=1M`)
— `libmount_utils_zfs.c:784-792` **[verified]**. Large dnodes exist precisely so
SA plus xattrs fit in the bonus buffer, which is the direct analogue of the
1 KiB ldiskfs MDT inode (`design-ldiskfs-scanner.md` §4.3).

**If that holds in practice, the scan is one sequential read per object and the
performance model of §11 applies. If it does not — if LMA commonly spills — every
object costs an extra random read and the model collapses.** The ldiskfs
prototype measured its equivalent (tier-2 rate **0.0%**, §17). *The ZFS
equivalent has not been measured, and it is the first thing to measure.*

---

## 5. Object identification and classification

Reuse `design-ldiskfs-scanner.md` §5 wholesale: LMA `lma_self_fid` is the FID,
the FID sequence decides the object's role, and IGIF handling is unchanged.

Two ZFS-specific notes:

- **The scrub path's own filter is a useful hint.** It accepts an object only if
  LMA is present and `!(lma_compat & LMAC_NOT_IN_OI)` and
  `!(lma_incompat & LMAI_AGENT)` (`osd_scrub.c:405-406` **[verified]**). Those
  two flags are a cleaner classification signal than anything the ldiskfs
  scanner had available.
- **Internal-object exclusion may be easier here.** On ldiskfs, `/CONFIGS/mountdata`
  and `/update_log_dir/*` carry `compat=0 incompat=0` and are indistinguishable
  from user files, forcing a hand-maintained denylist (the "Internal-object
  exclusion" question). On ZFS, pool-level objects (`MASTER_NODE_OBJ`, the SA
  registry, OI ZAPs) carry no Lustre LMA at all and fall out for free. **Whether
  Lustre's own internal objects on ZFS have the same zero-flag LMA problem is
  unverified** — measure with the same `lfs find` oracle before claiming it.

---

## 6. Consistency model — where ZFS is genuinely better

This is the section that differs most from the ldiskfs design, and in ZFS's
favour.

### 6.1 Scan a snapshot; get atomicity for free

ZFS is copy-on-write and a snapshot is atomic and near-free. **Scanning a
snapshot observes every object at one txg.** That eliminates, by construction
rather than by heuristic:

| ldiskfs scanner problem | On a ZFS snapshot |
|---|---|
| Torn reads mid-update (§8.2) | Cannot occur |
| Journal commit-window lag (~5–10 s) | Cannot occur |
| Validation heuristics + skip counting | Unnecessary |
| **Begin-to-end scan skew** — objects seen at different points in a long scan | **Eliminated** |

The last row is the notable one: scan skew was documented as unfixable for
*both* ldiskfs options (`option-comparison.md`). On ZFS it simply goes away.

**State the claim precisely.** A snapshot does not improve *freshness* — it
misses everything after the snapshot txg, exactly as Dilger noted. It improves
*internal consistency*: no "objects M..N absent, then present moments later."
These are different properties, and consumers doing aggregates, migration or
reporting care about the second one. Consumers needing recency belong on the
Changelog Input Scanner regardless of backend.

### 6.2 If scanning a live dataset instead

The same commit-window issue exists and is documented in-tree: `dmu_object_next()`
"does NOT find dnodes allocated in the current non-committed txg", which is why
`osd_otable_it_init()` forces `txg_wait_synced()` before iterating
(`osd_scrub.c:1545-1549` **[verified]**). A userspace scanner cannot force a txg
sync on a pool it does not own, so a live scan is *always* missing the open txg.

**Therefore: snapshot mode is the default, and live-dataset mode must warn.**

---

## 7. Implementation routes

Four were considered; the traversal layer should be swappable between the first
two.

| # | Route | Assessment |
|---|---|---|
| 1 | **libzpool** — own the objset read-only or a snapshot, `dmu_object_next()`, `dmu_bonus_hold()` → SA → DXATTR | **Start here.** Same code shape as the ldiskfs backend, full attribute access, works on exported pools. Cost: libzpool is an explicitly unstable internal API, version-coupled to the ZFS build |
| 2 | **`traverse_dataset()` with prefetch** — the machinery `zfs send`, scrub and resilver use; block-order traversal with the ZFS prefetcher pipelining I/O | The real performance answer, and the true analogue of "sequential read at device bandwidth". Same dependency as route 1, so build behind the same `lfu_target_ops` and swap in once route 1 is correct |
| 3 | **`zfs send` stream parsing** — parse `DRR_OBJECT` (dnode + bonus, hence SA + xattrs) and `DRR_SPILL` records | **Worth a separate spike.** No libzpool linkage, no pool access, runs on another machine, integrates with backup workflows. For an *MDT* the stream is nearly pure metadata since MDT objects hold no data. Weak for OSTs (carries file data); raw/encrypted sends (`-w`) are opaque and must be refused |
| 4 | **Channel programs (zcp)** | Rejected. Instruction-budget limited, no SA/xattr access; not viable at namespace scale |

Route 3 deserves emphasis because it is the only option with **no ZFS-internals
coupling at all** — which is exactly the property that makes the ldiskfs scanner
deployable on old servers, and the reason "offline use" is on the roadmap.

---

## 8. Parallelism, checkpoint and restart

- **Unit of work.** Object-ID ranges, the analogue of ldiskfs block groups. A
  scan can be split N ways by partitioning the object-ID space, since
  `dmu_object_next()` accepts a start position.
- **Checkpoint.** The object ID *is* the cursor — the same property osd-zfs uses
  for `store()`/`load()` (`osd_scrub.c:1761`, `:1792` **[verified]**). Restart is
  therefore trivial, and on a snapshot it is also *exact*, since the target
  cannot change under a resumed scan. This is strictly better than the ldiskfs
  case, where a resumed scan resumes against a moved target.
- **Rate limiting.** Needed for live-pool scans; unnecessary against an exported
  pool or a snapshot on idle storage.

---

## 9. Performance model

The ldiskfs arithmetic (`design-ldiskfs-scanner.md` §11.1) carries over in shape:
1M objects/sec at ≥1 GiB/s implies ~1 KiB read per object, i.e. one dnode. With
`dnodesize=auto` that is plausible — **conditional entirely on §4.4**.

**No ZFS numbers exist.** None of the measured figures transfer: 705k inodes/s
(ldiskfs scanner) and 105k objects/s (OSD path via OI Scrub) are both ldiskfs
measurements on one VM. Running [`throughput-test-plan.md`](throughput-test-plan.md)
against a ZFS MDT — for this scanner *and* for ZFS OI Scrub as the OSD-path proxy
— is required before any claim is made, and the plan needs one change: populate
with `dnodesize=auto` and verify the pool is not host-cached.

---

## 10. Testing

Reuse `design-ldiskfs-scanner.md` §13 in full — the `lfs find` + `lfs path2fid`
oracle is backend-independent and is what caught the internal-object leak on
ldiskfs. Three ZFS-specific additions:

1. **SA registry resolution test.** Build a dataset, mutate the SA layout
   (e.g. add projid to some objects and not others), assert the scanner still
   reads correct attributes. This is the §4.2 failure mode and it is silent.
2. **Snapshot atomicity test.** Scan a snapshot while a client creates and
   deletes files against the live dataset; assert the scanner's output is
   bit-identical across repeated runs of the same snapshot, and that skip and
   gap counters are zero.
3. **Encrypted-dataset refusal test.** Assert the scanner detects an unloaded key
   and exits with a diagnostic rather than emitting ciphertext-derived garbage.

---

## 11. Dependencies and packaging

- `libzpool`, `libnvpair`, `libuutil` (routes 1–2) — headers from
  `zfs-devel`/`libzfs-devel`. Version coupling is the main packaging risk and
  the reason route 3 is worth evaluating in parallel.
- No dependency on a mounted Lustre server, and none on the Lustre kernel
  modules.
- Privilege: read access to the pool devices, or to a snapshot; no root
  requirement beyond that.

---

## 12. Open questions specific to this module

| Topic | Question | Blocks |
|---|---|---|
| ~~**Inline LMA rate**~~ | **ANSWERED 2026-08-07 (§15):** yes — max bonus 636 B of ~832 B available, 1 spill block in 1351 objects | — |
| ~~**SA registry replication**~~ | **ANSWERED 2026-08-07 (§15):** correct on osd-zfs + ZFS 2.2.10; `sa_fail = 0` over 301k objects. Still unverified across *other* ZFS versions | Narrowed to the CI matrix question below |
| **libzpool version coupling** | Which ZFS versions must be supported, and is large-dnode handling uniform across them? | Packaging, CI matrix |
| **Send-stream route** | Is `DRR_OBJECT` + `DRR_SPILL` sufficient to reconstruct every attribute LFU needs, without libzpool? (§7 route 3) | Whether a dependency-free scanner is possible at all |
| ~~**Internal objects on ZFS**~~ | **ANSWERED 2026-08-07 (§15):** they do *not* fall out for free — 230 osd-zfs directories have an SA bonus and no xattrs, landing in `no-lma`. "Visible" stays correct; `no-lma` and `links == 0` must be reinterpreted on osd-zfs | — |
| **Pool must be exported** | The scanner needs the pool exported (`cachefile=none` + `multihost=on`, §15). Is "unmount the target first" acceptable operationally, or is a `--force-active` read of a quiesced-but-imported pool needed in practice? | Operational fit of Option 1 on ZFS |
| **Encrypted datasets** | Detect-and-refuse, or support with loaded keys? | Scope |
| **OST-side join** | Reconstructing file size from OST objects — zester's known bug area (stripe extent offsets) | OST scanning correctness |
| **Blocks semantics** | `doi_physical_blocks_512` is post-compression physical (matches ZFS `stat()`, differs from ldiskfs for compressible data). Should the Object Stream carry logical size, physical blocks, or both, so `blocks >` filters mean one thing across backends? | Filter semantics; found by the prototype (§14) |

---

## 13. Relationship to the OSD API scanner

These are complements, not competitors — the same relationship the ldiskfs
scanner has to the OSD path:

| | ZFS device scanner (this) | OSD API scanner |
|---|---|---|
| Exported / unmounted pool | Yes | No |
| Snapshot, point-in-time consistent | Yes | No |
| Server with no LFU kernel support | Yes | No |
| Runs on a different machine | Yes (route 3) | No |
| Live, current metadata | No — snapshot or last-synced txg | Yes |
| WBCFS and future backends | No | Yes |
| In-kernel filter pushdown | No | Yes |

The existence of this module weakens, but does not remove, the "the OSD path is
the only way to reach ZFS" argument in `architecture.md` §6c — which has been
corrected accordingly. The OSD path remains the only route to WBCFS, the only
route to live in-memory metadata, and the only route to in-kernel filtering.

---

## 14. Prototype status **[added v0.2, 2026-08-06]**

`src/lfu_scan_zfs.c` — single-threaded, route 1 (libzpool), builds clean with
`make zfs`, **16/16 tests passing** (`tests/run_tests_zfs.sh` against the
synthetic dataset built by `tests/mkzpool.sh`). Shares `src/lfu_lustre.h`
(LMA/FID/classification — renamed from `lfu_ldiskfs.h`, since it was always
backend-neutral) with the ldiskfs scanner, which still passes 17/17 after the
rename.

**Implemented:** snapshot and live-dataset open via `dmu_objset_own` ·
per-dataset SA registry resolution (§4.2) · dnode walk via `dmu_object_next` ·
SA attribute extraction · DXATTR nvlist unpack → LMA → FID (§4.3) · the §5
classification ladder · tier-0 filters · skip counting (`sa_fail`) ·
live-dataset warning (§6.2) · max-bonus-size reporting (§4.4 evidence).

**Validated by the prototype, not just asserted:**

- The full §4 read path works from userspace on an imported pool, including
  against a snapshot — dataset open, SA registry, dnode walk, DXATTR unpack.
- **Snapshot atomicity (§10 test 2):** repeated scans of the same snapshot are
  bit-identical while the live dataset churns; post-snapshot creates/deletes
  are invisible; `sa_fail = 0`.
- The classification ladder reproduces the ldiskfs scanner's behaviour on
  synthetic objects covering every branch (visible / internal-by-seq /
  internal-by-flag / OST-by-IDIF / agent / bad-incompat / no-LMA).
- ZFS-internal objects (master node, SA registry, ZAPs) fall out via
  `doi_bonus_type != DMU_OT_SA` with no denylist — the §5 conjecture, at least
  for pool-level objects.

**Found by building — gotchas future work inherits:**

- **`FTAG` is `__func__` in libzpool**, so `dmu_objset_own()` and
  `dmu_objset_disown()` called from different functions trip the
  `ds_owner == tag` assert. Use one file-scope tag.
- **Distro header packaging is incomplete**: `zfs_ioctl.h` is not shipped, so
  `dmu_objset.h` cannot be included (`dmu.h` declares everything needed), and
  `zfs_acl.h` must precede `zfs_sa.h`.
- **`doi_physical_blocks_512` is post-compression physical.** With
  `compression=on` (the OpenZFS 2.2 default) a compressible 256 KiB file
  reports 8 blocks. This matches `stat()` on ZFS but differs from ldiskfs
  semantics — a `blocks >` filter behaves differently across backends for
  compressible data. Carried to §12 as an open question.
- Userland/kmod version skew (2.2.2 userland, 2.4.1 kmod) was harmless for
  this workflow: the pool is created by the userland feature set, and the
  scanner never talks to the kmod.

**Not yet:** parallel scan over object-ID ranges (§8) · `traverse_dataset()`
prefetch path (§7 route 2) · linkea/LOV parsing · Object Stream encoding —
output is text · OST-side specifics · **any run against a real osd-zfs MDT**.

**The fidelity gap, stated plainly:** the synthetic rig creates objects through
the ZPL with hand-written `trusted.lma` xattrs. That exercises enumeration, SA
reads, DXATTR unpacking and classification — but not objects created by
osd-zfs itself, whose SA layout, dnode sizing and internal-object population
may differ. The §4.4 inline-LMA question and the §10 oracle test still require
a real Lustre-on-ZFS MDT, which needs a ZFS-enabled Lustre server build the
lab does not currently have.

## 15. Verified against a real osd-zfs MDT **[added v0.3, 2026-08-07]**

The §14 fidelity gap is **closed**. Full results:
[`zfs-mdt-verification-2026-08-07.md`](zfs-mdt-verification-2026-08-07.md) —
Lustre `v2_17_55` + OpenZFS 2.2.10 on Rocky 9.8, single-node `llmount.sh
FSTYPE=zfs`, 1,027-FID `lfs path2fid` oracle and a 301k-object scale run.

Headlines, each of which changes something above:

- **§4.4 confirmed, and it was load-bearing.** Max bonus 636 B against ~832 B
  available in a 1 KiB dnode; **1 spill block in 1351 objects**. One dnode read
  really does get SA attributes + LMA + LOV + linkea.
- **§4.2 confirmed** — registry replication is correct; `sa_fail = 0` over 301k
  objects.
- **§6.1 confirmed on a real target** — snapshot scans bit-identical, live scan
  shows the open-txg discrepancy §6.2 predicts.
- **§10 oracle: zero misses** — every namespace FID found. One false positive
  in `visible` (`[0x200000400:0x1:0x0]`, a format-time OSD object with a
  normal-sequence FID and no path); count does not grow with the namespace.
- **§5's conjecture is FALSIFIED.** ZFS-internal objects do fall out via
  `doi_bonus_type`, but osd-zfs's *own* directory hierarchy — 230 objects on a
  fresh MDT — are ZPL directories with an SA bonus and no xattrs, so they pass
  that gate and land in `no-lma`. The ladder's *outcome* stays correct; its
  stated reason did not. Corollary: **"no-LMA implies suspicious" is false on
  osd-zfs**, and `links == 0` does not mean "pending delete" there either.
- **A blocker no rig could show:** Lustre pools are created with
  `cachefile=none` and `multihost=on`, so libzpool could not open the MDT at
  all (`ENOENT`, then `EREMOTEIO` — the latter even on a cleanly exported
  pool). Fixed by a `zdb -e`-style device-scanning import (`-e`/`-p`), which
  makes explicit that **this scanner requires an exported pool**.
- **ZFS throughput: 87,600 obj/s at `-j 1`, 274,000 at `-j 24`** (3.4×), file
  vdev, 8 vCPUs. §8's parallel ranges are now implemented; the plateau is
  libzpool lock contention, not core count.
- **§9's performance model needs rewriting.** Profiling killed the standing
  assumption: the per-object DXATTR `nvlist_unpack` costs **0.0%**, and the
  entire cost is the DMU object path (`dnode_hold_impl` and the two callers
  that each took their own hold). §7 route 2's prefetch — the design's
  nominated fix — is aimed at an I/O stall the profile does not show.

## References

**[verified]** against `../lustre-release` @ `v2_17_55-2-gd717692511`:

- `lustre/osd-zfs/osd_scrub.c:1672` — `dmu_object_next()`, object enumeration
- `lustre/osd-zfs/osd_scrub.c:1545-1549` — `txg_wait_synced()` and the uncommitted-txg caveat
- `lustre/osd-zfs/osd_scrub.c:395-407` — LMA lookup from the DXATTR nvlist, `LMAC_NOT_IN_OI` / `LMAI_AGENT` filtering
- `lustre/osd-zfs/osd_scrub.c:1746-1817` — the otable iterator, `rec()` / `store()` / `load()`
- `lustre/osd-zfs/osd_xattr.c:47-70` — `__osd_xattr_load()`, `SA_ZPL_DXATTR` → `nvlist_unpack()`
- `lustre/osd-zfs/osd_object.c:188-248` — the SA attribute set Lustre uses
- `lustre/osd-zfs/osd_handler.c:981-988` — SA registry lookup and `sa_setup()`
- `lustre/utils/libmount_utils_zfs.c:784-792` — `dnodesize=auto`, `recordsize=1M`

External: [zester](https://github.com/iu-hpfs/zester) (IU HPFS, LUG'17) — read
for MDT↔OST join logic and size-reconstruction traps, not as a base.
