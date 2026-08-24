# Snapshot-then-scan — the userspace scanner against a filesystem in service

**Date:** 2026-08-24 · **Status:** proposal · **Needs no kernel change** ·
**Backends:** ldiskfs now, ZFS blocked (§7)

`llapi_scan_device()` reads a target's inodes off its block device. That is
what makes it fast, and it is also why it refuses a target that is in service.
This is a way to point the scanner we have already shipped at a **live**
filesystem, using a primitive Lustre already provides, without waiting for the
2.19 OSD scanner or for any RPC work.

**Read §8 first.** The barrier window is short and easy to like; the snapshot's
copy-on-write cost runs for the whole scan, sits in the MDT's write latency
path, and is cheap on the backend our scanner cannot read and expensive on the
one it can. That is the deciding factor, not the freeze.

## 1. The problem

A target in service cannot be read safely from userspace:

| Backend | What happens today | Where |
|---|---|---|
| ZFS | `-EBUSY` for a pool in `POOL_STATE_ACTIVE` — refused outright | `libscan_zfs.c:170` |
| ldiskfs | Runs, but reads a device being written underneath it | `open-questions.md`, *Torn metadata* |

The ldiskfs case is the dangerous one, because it *appears* to work. The
scanner opens with `EXT2_FLAG_IGNORE_CSUM_ERRORS` precisely because *"a mounted
target yields torn reads, which are counted and skipped rather than fatal"*
(`libscan_ldiskfs.c:29-36`). Objects lost that way are counted in
`ss_skipped`, so the damage is visible — but it is still damage, and the
exposure has never been measured against a write-heavy filesystem.

The 2.19 answer is the in-kernel OSD scanner, which reads objects through the
OSD in memory and never touches the raw device. That is the right end state.
This document is about the interval before it.

## 2. Why the obvious mitigations do not work

**`fsfreeze` is not available on a Lustre target.** `FIFREEZE` needs
`super_operations::freeze_fs`, and nothing in `osd-ldiskfs`, `mdt` or
`obdclass` implements it — the ldiskfs superblock is mounted internally by the
OSD and is not the thing `/mnt/mdt0` exposes. So the usual "freeze, snapshot,
thaw" recipe has no entry point here.

**A per-device snapshot alone is not enough under DNE.** Snapshotting each MDT
independently gives each one a consistent image of *itself*, at a different
instant from its neighbours. Remote directory entries and cross-MDT references
would then be captured on either side of an update, and a merged scan would
report a namespace that never existed.

Both point at the same requirement: the quiesce has to be **filesystem-wide**
and it has to be **Lustre's**, not the block layer's.

## 3. What Lustre already provides

`lctl barrier_freeze FSNAME [TIMEOUT]` — implemented in
`lustre/target/barrier.c`, registered per MDT, coordinated by the MGS. Its own
contract (`barrier.c:115-147`) is exactly the guarantee a snapshot needs:

> We use two-phases barrier to guarantee that after the barrier setup:
> 1) All the MDT side pending async modification have been flushed.
> 2) Any subsequent modification will be blocked.
> 3) All async transactions on the MDTs have been committed.

Phase 1 sets the barrier flag and calls `dt_sync()`; because in-flight client
requests can dirty things after that, it calls `dt_sync()` **again** once they
drain. Phase 2, driven by the MGS across every instance, calls `dt_sync()` a
final time so all async transactions are committed locally. On ldiskfs
`dt_sync()` reaches `osd_sync()`, which is `s->s_op->sync_fs(s, 1)` —
a synchronous sync, so the jbd2 journal is **committed to disk**.

This is not a repurposing. The barrier was built for
`lctl snapshot_create`, which takes `-b|--barrier [on|off]` and is the
supported way to take a consistent Lustre snapshot today. The only reason we
cannot simply use `snapshot_create` is that `lustre/utils/lsnapshot.c` shells
out to `zfs` throughout and has no ldiskfs path.

**So: the hard part — cluster-wide, on-disk, quiesced consistency — already
exists and is backend-agnostic. What is missing for ldiskfs is only the
snapshot step itself.**

## 4. The sequence

```
lctl barrier_freeze $FSNAME 30        # all MDTs: block writes, dt_sync x3
    on each MDS, for each MDT device:
        lvcreate -s -n mdt0-scan -L 64G /dev/vg/mdt0      # or dmsetup
lctl barrier_thaw $FSNAME             # service resumes

    lfind --device /dev/vg/mdt0-scan --type f --uid 1000  # scan at leisure
    ... merge the per-MDT streams ...

    lvremove /dev/vg/mdt0-scan         # release the COW space
```

| Step | Duration | Blocks the filesystem? |
|---|---|---|
| `barrier_freeze` | seconds (bounded by `TIMEOUT`) | **yes**, from phase 1 |
| snapshot create | milliseconds (LVM/dm is O(1) metadata) | yes, inside the window |
| `barrier_thaw` | immediate | ends the window |
| the scan | minutes to an hour | **no** |
| `lvremove` | immediate | no |

**The write barrier is held only for the snapshot creation**, not for the scan.
That is the whole point: a scan of 4B objects can take an hour, and the
filesystem is in service for all but the first few seconds of it.

### 4.1 What is actually frozen, and for how long

This is the first objection the design will meet, so it is worth being exact.

`barrier_entry()` is called from **`mdd_trans_create()`**
(`lustre/mdd/mdd_trans.c:39`) — the point at which a metadata modification
opens a transaction. That is the whole gate. So during the window:

| | Behaviour |
|---|---|
| creates, unlinks, renames, setattr | **paused** |
| lookup, getattr, readdir, statfs, open-for-read | unaffected — no transaction |
| OST data I/O | unaffected — the barrier is on MDTs only |

Blocked modifications **wait rather than fail**: the gate returns
`-EINPROGRESS`, which is retryable, so applications see a pause and not an
error.

**The barrier cannot be left set by a dead process.** Each instance carries a
deadline (`bi_deadline`, set from the `TIMEOUT_SECONDS` argument) and moves to
`BS_EXPIRED` when it passes (`barrier.c:351`), thawing without operator
action. That is what makes this safe to script.

**What makes the window longer than milliseconds** is the drain: phase 1 must
flush pending async modifications and phase 2 must commit all async
transactions, three `dt_sync()` calls in total. On a busy MDT with a lot of
dirty state that is the variable cost, bounded by `TIMEOUT` but not guaranteed
small. Measuring it under load is part of §9 and should not be assumed.

## 5. What the snapshot contains, and why no journal replay is needed

The scanner does not replay the journal — it opens read-only with
`EXT2_FLAG_SKIP_MMP | EXT2_FLAG_SOFTSUPP_FEATURES | EXT2_FLAG_64BITS |
EXT2_FLAG_IGNORE_CSUM_ERRORS` and reads on-disk state as it stands
(`libscan_ldiskfs.c:35`). On a snapshot of a live filesystem that would be a
real problem: the image would be crash-consistent with a dirty journal, and
inodes whose updates were still in the journal would read stale.

The barrier removes exactly that. After phase 2, `sync_fs(s, 1)` has committed
the journal on every MDT, so the snapshot contains a filesystem with **nothing
outstanding in the journal**. No replay is needed because there is nothing to
replay.

The same argument disposes of torn reads. Nothing is writing the device during
the snapshot window, so no block can be caught mid-write, and the
`IGNORE_CSUM_ERRORS` tolerance is never exercised. **That gives a directly
measurable acceptance criterion: `ss_skipped` should be 0 on a snapshot scan
where it is non-zero on a live one** (§9).

## 6. Why this is worth doing even though 2.19 supersedes it

- It uses code that is **already written, reviewed and lab-verified** — the
  ldiskfs backend, `lfind(8)`, and the filter pushdown.
- It needs **no kernel change, no new RPC, no wire format**, so it is not
  blocked on the Object Stream decision.
- It answers the question `open-questions.md` calls *"Blocks: confidence in the
  primary initial deliverable"* by sidestepping it rather than measuring it.
- The consistency it gives is **stronger** than the 2.19 remote scan's. The
  HLD accepts that a live scan is non-atomic and lags by "possibly tens of
  seconds"; a barrier-quiesced snapshot is a true point-in-time across all
  MDTs. For consumers that must not miss files — trash purge, tier migration,
  HSM archival — that is a real difference, not a nicety.

## 7. Backend coverage

**ldiskfs: works.** LVM or device-mapper gives a frozen block device, and
`llapi_scan_device()` reads it exactly as it reads a stopped target.

**ZFS: blocked, and not by the snapshot.** `zfs snapshot` is cheap and
`lctl snapshot_create` already does the barrier-plus-snapshot dance. The
obstacle is on our side: `scan_zfs_open()` imports the pool with
`spa_import()`, and refuses a pool in `POOL_STATE_ACTIVE`
(`libscan_zfs.c:170`). A ZFS snapshot lives *inside* the still-imported pool,
so our scanner cannot reach it. The comment on that refusal names the open
question directly:

> Whether a quiesced imported pool can be read safely is exactly the open
> question on the ticket; until it is answered the honest response is EBUSY,
> not a wrong scan.

There is a partial answer today: `lctl snapshot_mount` mounts a Lustre snapshot
read-only, which `llapi_scan_namespace()` can walk — but that is the slow
client path, which defeats the purpose. **Resolving the imported-pool question
is what unlocks ZFS here**, and it is worth doing on its own merits.

**OSTs:** the same sequence works, though the barrier is documented as a write
barrier on MDTs; an OST scan's consistency requirements are weaker (object
existence and size), so this needs stating rather than assuming.

## 8. Cost — and the strongest argument against this design

The barrier window is short and is *not* the main cost. **The snapshot's
copy-on-write overhead is, and it lasts for the whole scan.** This section is
the case against the approach; it should be read before the case for it.

### 8.1 The real trade is not what §4 makes it look like

With an LVM/dm snapshot held, every write to a not-yet-copied region becomes
read-original → write-to-COW → write-new: up to three I/Os where there was one,
plus COW table lookups, **in the latency path of every create, unlink and
rename**. That is the MDT — the most latency-sensitive device in the
filesystem, usually on its fastest storage.

So the trade is not "a few seconds of paused writes". It is:

> a few seconds of paused writes **plus degraded metadata write latency for the
> entire duration of the scan**

An hour-long scan of a large MDT means an hour of that. Stated plainly, this is
a worse bargain than the freeze window, and any presentation of this design
that leads with the barrier and buries the COW cost is misleading.

### 8.2 The failure mode loses the whole run

COW space is consumed in proportion to *write rate × scan duration*. If the
reservation fills, the snapshot is **invalidated and dropped**, and the scan
produces nothing — an hour in, with no partial result. Sizing the reservation
requires predicting write volume across the scan window, which is precisely the
quantity that is unknown on a busy filesystem.

### 8.3 The economics are inverted across the two backends

| | Snapshot cost | Our scanner |
|---|---|---|
| **ZFS** | near-free: natively copy-on-write, so a snapshot is retained references and writes were already going to new blocks | **blocked** — `POOL_STATE_ACTIVE` → `EBUSY` |
| **ldiskfs** | expensive: COW bolted on top of an overwrite-in-place filesystem | works |

**The backend where snapshots are cheap is the one where the scanner cannot
read them; the backend where the scanner works is the one where snapshots hurt
most.** This is not coincidence — the same property (overwrite-in-place versus
redirect-on-write) drives both halves. It is the single strongest argument
against the design as it stands, and it means **resolving the ZFS
imported-pool question (§7) is worth more than any refinement of the ldiskfs
path.**

### 8.4 What actually mitigates it

- **LVM thin snapshots** instead of classic dm-snapshot — materially lower
  overhead, though not free.
- **Array-level snapshots** where the storage does redirect-on-write — near-zero
  write penalty, and many sites already have this.
- **Scanning fast.** The exposure is write rate × *scan duration*, and duration
  is the one term we control; it is what the device scanner is for.
- **Not needing it.** The 2.19 OSD scanner reads objects in memory through the
  OSD and imposes no snapshot at all. This approach is a stopgap and should be
  argued as one.

**Recommendation:** viable on ldiskfs *with thin or array-level snapshots*,
poor with classic dm-snapshot, and superseded by the OSD scanner. Do not
propose it without §8.1 and §8.3 attached.

## 9. Validation

The acceptance case that makes this real, on a write-heavy filesystem:

1. Populate, then start a sustained metadata write load.
2. Scan the **live** device. Record `ss_seen`, `ss_emitted`, `ss_skipped`.
3. `barrier_freeze` → snapshot → `barrier_thaw`, load still running.
4. Scan the **snapshot**. Record the same counters.
5. Assert: `ss_skipped == 0` on the snapshot, and non-zero on the live scan
   under load. That is the torn-read exposure, measured rather than argued.
6. Diff the FID sets. The snapshot's set must be internally consistent — every
   FID's parent resolvable within the same image — where the live scan's need
   not be.
7. Confirm the barrier window with timestamps around step 3's three commands,
   and that no client I/O failed, only paused. Record the window separately
   for an idle and a loaded filesystem: the drain in §4.1 is the variable
   part, and the loaded number is the one that decides whether this is
   acceptable in production.

Step 5 is the one that settles `open-questions.md`'s *Torn metadata* entry
either way: if the live scan's `ss_skipped` is 0 under real load, the concern
was overstated and this whole document is optional; if it is not, the number is
the argument for it.

## 10. What would have to be built

Very little, which is the appeal:

- **Orchestration.** The sequence in §4 across N MDS nodes. A script is enough
  to prove it; `lctl snapshot_create` growing an ldiskfs/LVM path
  (`lustre/utils/lsnapshot.c`) is the supportable version.
- **A merge step.** `lfind` scans one target per invocation, deliberately.
  Merging per-MDT streams is a userspace concatenation today — and the HLD is
  explicit that userspace merge is *"a staging artefact, not the end state"*.
- **Nothing in the kernel.** The barrier is shipped; the scanner is shipped.

## 11. What it does not solve

- **LMR duplicates.** Merging streams from N MDTs yields duplicate FIDs for
  mirrored inodes. Unaddressed in every HLD revision; it lands on the record
  layout. See `open-questions.md`.
- **WBC.** Metadata still in client RAM has never reached the server and so is
  not in any snapshot. The barrier blocks *server-side* modification; it does
  not flush a client-side cache.
- **Paths.** A device scan yields FIDs and linkea names. `fid2path` per match
  is unchanged by any of this.
- **Per-user access control.** This is an admin operation on a raw block
  device. It cannot be exposed to an unprivileged user, which is exactly the
  boundary the HLD draws for the 2.19 path too.

## 12. Relationship to the 2.19 remote scan

This is not an alternative architecture, and should not be presented as one. It
is a way to get server-side scanning value out of the 2.18 deliverables while
the OSD scanner, the Object Stream format and the bulk-RPC modules are built.
Every piece of it — the demand mask, the filter pushdown, the record, the
predicates — is the same code the remote path will use. When
`OBD_IDX_READ`-shaped scan RPCs land, this becomes the offline/point-in-time
option rather than the only one.

## References

- `lustre/target/barrier.c:115-215` — the barrier contract and `dt_sync()` calls
- `lustre/osd-ldiskfs/osd_handler.c` — `osd_sync()` → `sync_fs(s, 1)`
- `lustre/utils/lsnapshot.c` — `lctl snapshot_create`, ZFS-only today
- `lustre/utils/libscan_ldiskfs.c:29-36` — the scanner's open flags and why
- `lustre/utils/libscan_zfs.c:105-174` — the `EBUSY` refusal and its rationale
- `docs/open-questions.md` — *Torn metadata when scanning a live ldiskfs device*
- `docs/Lustre_Find_Utility-High_Level_Design.pdf` — OSD API scanner, §Server-Side Changes
