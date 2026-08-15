# Parallel Enumeration Behind the OSD API — Step 5, the Design

**Date:** 2026-08-15
**Follows:** `scrub-decomposition-2026-08-07.md` steps 1–4 (iterator floor,
fan-out, `rec()` attributes, ring), `design-osd-scanner.md` §8.1 (the
singleton), and the LU-20591 exchange of 2026-08-15 in which we committed
publicly to prototype this and post the scaling curve.
**Status:** **superseded in its predictions by
[`parallel-osd-measured-2026-08-15.md`](parallel-osd-measured-2026-08-15.md)**,
which ran the matrix below on a fresh ldiskfs lab the same day: 2.03M obj/s at
2 threads (2.4x the singleton), correctness identical to the singleton, the
wall identified as the kernel's global `inode_hash_lock`, and LFSCK
coexistence demonstrated. This document remains the design record for the
patch and the harness. Where §4 guesses at outcomes, read the measured doc.

## 1. What the singleton actually binds

Steps 1–4 left one lever untouched.  Fan-out (step 2) parallelises the
*per-object work* behind the enumerator; `rec()` attributes (step 3) then made
most of that work free; the ring (step 4) costs nothing.  Every one of those
numbers — 832k enumerate, 793k with attributes, 796k end-to-end — is a
**single-enumerator** number, and on ZFS the enumerator (~110–130k) is the wall
that fan-out could not move at all.  The only lever left is more enumerators.

`design-osd-scanner.md` §8.1 recorded that as impossible: `od_otable_it` is one
pointer per `osd_device`, `osd_otable_it_init()` returns `-EALREADY` on a second
call, and the enumerator behind it is the single `OI_scrub` kthread that
`scrub_start()` launches.  All true — but it binds the **otable iterator
object**, not the walk.  Reading `osd_inode_iteration()` (`osd_scrub.c:981`)
again with sharding in mind:

- Every piece of walk state — `bg`, `offset`, `gbase`, `bitmap`, `start` —
  lives in one `struct osd_iit_param`, plus a `pos`/`count` pair.  Nothing
  is global except the pointer to the singleton itself.
- The two per-object primitives, `osd_iit_next()` (find the next set bit
  in the group's inode bitmap) and `osd_iit_iget()` (`osd_iget` + LMA, and
  since step 3 the attributes), take `param`, `info` and `dev`; their only
  shared writes are the benign `os_ls_fids[]` max-tracking and
  `os_has_ml_file`.
- That is exactly the shape the userspace ldiskfs scanner shards with a
  per-worker `ext2_filsys` and `ext2fs_inode_scan_goto_blockgroup()`, byte-
  identical output at `-j 1/4/8/24` (`ldiskfs-mdt-parallel-2026-08-07.md`).

Relaxing `-EALREADY` alone would buy nothing: the producer would still be the
one scrub kthread, and the preload cache is per-`od_otable_it`.  What is needed
is an iterator instance that **is not the device's otable iterator** — no
registration, no `scrub_start()`, no preload cache handed across threads — and
then N of them are simply N walks over N inode ranges.

## 2. The patch: `DOIF_PARALLEL` — a private iterator instance

`patches/parallel-it-v2_17_55.patch` (364 lines, stacks on
`rec-attr-v2_17_55.patch` + `rec-attr-zfs-v2_17_55.patch`; verified to apply
on `v2_17_55` and on current master `v2_17_56-50-g7fc2dba7b7`).

**API** (`dt_object.h`): one new init flag,

```c
	/* A private iteration: not registered as the device's otable
	 * iterator, no OI scrub started or stopped, no preload window.  Any
	 * number may run concurrently on one device, alongside OI scrub and
	 * LFSCK.  Consumers that shard the object table start each instance
	 * with load() and stop it when store() leaves the shard (LFU). */
	DOIF_PARALLEL	= 0x0020,
```

No new ops, no new record type.  The `dt_it_ops` contract already has what
sharding needs: `load(hash)` positions an instance at `hash + 1`, `store()`
returns the current object number, `next()` returns 1 at the end of the table.
A shard is `init(DOIF_PARALLEL) → load(start-1) → rec()/next() until
store() ≥ end → fini()`.  Composes with `DOIF_ATTR`.

**osd-ldiskfs** (`osd_scrub.c`, `osd_internal.h`):

- `osd_otable_it_init()`: on `DOIF_PARALLEL`, allocate an `osd_otable_it`
  with `ooi_private = 1`, do **not** take `od_otable_mutex`, do not set
  `dev->od_otable_it`, do not call `scrub_start()`.  Slot 0 of the existing
  `ooi_cache` (and `ooc_attr[0]`) holds the current record so `rec()` and
  `store()` work unchanged.  A device-level `atomic_t od_otable_users`
  counts live instances; `osd_scrub_cleanup()` asserts it is zero, the same
  guarantee level the singleton has today.
- `osd_otable_it_fini()`: private → release the held group bitmap, drop
  the count, free.  No `scrub_stop()` — which incidentally is the same
  latent bug Jinshan's `DOIF_NOSCRUB` fixes: an out-of-OSD consumer's
  `fini()` stopping a scrub it never started.
- `osd_otable_it_next_private()` (new, ~80 lines): the group loop of
  `osd_inode_iteration()` with the two couplings removed — no 64-entry
  preload cache, no scrub pacing.  Same `osd_iit_next()` /
  `osd_iit_iget(..., is_scrub=false, la)` primitives inline, same UNINIT and
  `itable_unused` group skips, so **the object set and attributes are
  exactly what the otable iterator returns**.  The group bitmap is kept
  across calls (the original re-reads it every 64-object batch) and released
  on group change and in `fini()`.  It never calls
  `osd_scrub_check_update()`, so it is inherently the `lfu_noverify`
  configuration.
- `osd_otable_it_next()`: one-line dispatch on `ooi_private`.
- `osd_otable_it_load()`: the position/`param` setup is reused verbatim;
  only the scrub-specific `LASSERT(!os_partial_scan)` and `wake_up_var()`
  are skipped for private instances.

**osd-zfs** (`osd_scrub.c`, `osd_internal.h`): the same shape, smaller,
because the ZFS `next()` is already self-contained (`dmu_object_next()` →
xattr load → LMA, plus `DOIF_ATTR` from step 3):

- init: private instance, no `od_otable_sem`, no `od_otable_it`, no
  `scrub_start()`.  **No `txg_wait_synced()` either** — a scan of a live
  target is stale by design (HLD), and N shards would otherwise force N pool
  syncs.
- `next()`: three guards — skip the wait on `os_pos_current`, skip the
  scrub throttle/wakeup (a private iterator paces nobody), and **always run
  the 256-dnode prefetch window** rather than only at `os_full_speed`.  The
  window is per-iterator state, so each shard prefetches its own range.
- `load()`: private instances start the `dmu_object_next()` search at
  `hash` rather than `hash + 1`, so that — as on ldiskfs — everything from
  `hash + 1` on is returned.  See §5 for why.

## 3. The harness: `src/kernel/lfu_par.c`

One-shot module like `lfu_it`; runs at insmod, reports to dmesg, returns
`-ENODEV`.  Parameters: `dev`, `nthreads` (default 4), `chunk` (default
65536 object numbers), `recattr` (default 1), `private` (default 1), `limit`.

- **Dynamic sharding.**  The object-number space is cut into fixed chunks
  handed out from a shared atomic cursor.  This matters: on a young MDT the
  allocated inodes are packed into the low block groups (2M inodes in 62 of
  ~1000 groups on the 08-07 lab), so static equal-range shards would leave
  N−1 threads idle and make the measurement meaningless.  With dynamic
  chunks a thread that lands on an unallocated region walks its UNINIT
  groups in microseconds and takes the next chunk.  `chunk` should be a
  multiple of the inodes-per-group (32768 on the 08-15 lab; `dumpe2fs -h`) so
  shards are group-aligned and no two threads hold one group's bitmap.
- **Termination without knowing the table size.**  A chunk whose `load()`
  or `next()` returns 1 found nothing at or after its start; since chunks
  are handed out in increasing order, every later chunk is empty too and the
  thread sets a global `done`.  Threads finish their current chunk first, so
  nothing is dropped.
- **Chunk boundary.**  A shard counts only objects with `store() < end`;
  the object that ends it belongs to the next chunk and is deliberately
  re-found there.  Cost: one `iget()` per chunk beyond the boundary, warm.
- **`private=0` baseline in the same boot.**  Runs the unpatched singleton
  path (`DOIF_RESET|DOIF_OUTUSED`, one thread) — `lfu_it` inside the same
  harness — so the A/B does not depend on cross-lab warm-rate
  reproducibility, which the 832k-vs-390k gap says we do not have.  For
  parity it should run with `lfu_noverify=1`, since the private path never
  verifies OI.
- **Correctness without a userspace dump.**  Every run prints an
  order-independent FID checksum (`fidsum`), `objects` and `attr_ok`.  On
  one MDT those three must be identical at every `nthreads`, in both modes,
  or the sharding is wrong.  The step-4 FID-set diff against the device
  scanner remains the strong statement; this is the cheap one that runs on
  every row.
- Per-thread object counts and wall times are printed to expose imbalance.

## 4. What to measure, and what would count as an answer

Same lab type as before (GCP c3-standard-8, 2M `createmany` objects), warm
rows for CPU cost, one cold row per backend for the operational number.

| Row | ldiskfs | ZFS |
|---|---|---|
| `private=0` (singleton, `lfu_noverify=1`) | the step-1 floor, this boot | same |
| `private=1 nthreads=1` | is the private walk itself slower or faster than the preload-cache path? | same |
| `nthreads=2, 4, 8` | **the scaling curve** | **the scaling curve** |
| `recattr=0` at the best `nthreads` | attribute cost under parallelism | same |
| cold, best `nthreads` | does parallel enumeration change the device-bound row? | same |

What the numbers would mean:

- **ldiskfs.**  Single-thread ~800k; the 1M target is 25% away.  The warm
  profile at one thread is already ~22% spinlock pair, 9.7%
  `find_inode_fast`, 8.3% `__find_get_block` (`scrub-decomposition` §ldiskfs)
  — icache hash and buffer-cache contention that more threads make worse.
  The userspace scanner avoids all of it by parsing inodes out of a private
  bitmap with no kernel inode cache; the in-kernel path cannot.  So the
  expectation is **real but sublinear** scaling; ≥1.3× at 2–4 threads clears
  the target, and a `perf` profile of the plateau tells us whether the wall
  is `inode_hash_lock`, the per-sb `s_inode_list_lock` in `iput`/`evict`, or
  the buffer cache.  If it does not scale at all, that profile is the
  result: it would mean the LFU-relevant path needs `iget`-free inode reads
  (raw itable block parse, as the userspace scanner does), which is a much
  bigger conversation.
- **ZFS.**  Here parallel enumeration is the *only* lever, and the evidence
  it works is already in hand: the userspace scanner shards by object-ID
  chunk over one shared objset (`lfu_scan_zfs.c:408,418`) and went 87.6k →
  274k at `-j 24`, CPU-bound in the same DMU hold/lock machinery the kernel
  path showed (`mutex_lock` 12%, `_raw_spin_lock` 10%, `zrl_add/remove`,
  `dbuf_hold/rele`).  If the in-kernel shards match that curve, Option 2 on
  ZFS becomes competitive on speed rather than only on liveness/WBCFS —
  which changes the "ZFS posture" recorded in `scrub-decomposition` step 2.
- **Cold.**  On ldiskfs the cold row was device-bound at ~166–174k for both
  options and flat at every `-j` for the device scanner.  Expect the same:
  threads should not move it.  If they do, it means the singleton was
  leaving I/O parallelism on the table (no readahead across groups), which
  would be its own useful finding.

## 5. Two things found on the way

- **The ZFS otable iterator's `load()` skips one object.**  `load(hash)`
  sets `ooi_pos = hash + 1` ("start from the next one"), but
  `dmu_object_next()` returns objects strictly *after* `*objectp`, so the
  first `next()` yields the first object `> hash + 1` — object `hash + 1`
  itself is never returned.  On ldiskfs, `load(hash)` correctly returns
  from `hash + 1`.  Consequence for the existing code: an LFSCK that
  checkpoints `store()` and resumes with `load()` on osd-zfs skips one
  object per restart.  The patch fixes this for private instances only
  (`ooi_pos = hash`) and leaves the default path untouched; it should be
  raised upstream separately, and it needs confirming against the ZFS
  source of the lab kernel (`dmu_object.c`, `start_obj = *objectp + 1`)
  before we say it in public.
- **`DOIF_PARALLEL` on an unpatched OSD** is silently ignored, so the second
  thread's `init()` gets `-EALREADY` and the harness aborts — the singleton
  demonstrating itself.  Any real consumer must treat `-EALREADY` from a
  `DOIF_PARALLEL` init as "this OSD does not support parallel iteration",
  not retry.  A feature bit would be cleaner than an error code; noted for
  the eventual submission.

## 6. Relation to LU-20591

Jinshan's `DOIF_NOSCRUB` (`= 0x0010`, colliding with our `DOIF_ATTR`) makes
the singleton not start a scrub but keeps it a singleton; his walk is
therefore single-threaded for exactly the reason ours was, and we said so on
the ticket.  `DOIF_PARALLEL` is the next step past `DOIF_NOSCRUB`: it
subsumes it (no scrub) and removes the singleton for private instances.
When rebasing onto his series, `DOIF_ATTR` moves to a free bit and
`DOIF_PARALLEL` implies `DOIF_NOSCRUB`.  Because private instances never
touch `od_otable_it`, **LFU and LFSCK/OI-scrub can run at the same time**,
which closes `design-osd-scanner.md` §8.1 and open-question K8 as far as the
device is concerned (they still compete for I/O and CPU).

## 7. Build and run

Nothing here has been compiled: the workstation's kernel is 7.0 and the
`lustre-release` tree is client-configured, so `osd-ldiskfs` does not build
locally.  On a lab (same recipe as `scrub-decomposition` step 1; a source
build of `lustre-release` is required for the patched OSD):

```sh
# in the lustre-release checkout, on the lab
patch -p1 < lfu/patches/rec-attr-v2_17_55.patch
patch -p1 < lfu/patches/rec-attr-zfs-v2_17_55.patch     # ZFS lab only
patch -p1 < lfu/patches/parallel-it-v2_17_55.patch
make -j$(nproc)
# module-only install on a mounted system (the full `make install` fails
# on the busy /sbin/mount.lustre — scrub-decomposition step 1 method note)
cp lustre/osd-ldiskfs/osd_ldiskfs.ko /lib/modules/$(uname -r)/extra/lustre/fs/ && depmod -a
# ... unmount, rmmod osd_ldiskfs, remount; then confirm the patched module:
modinfo osd_ldiskfs | grep -q lfu_noverify && echo patched

# harness
cd lfu/src/kernel
make -C /lib/modules/$(uname -r)/build M=$PWD LUS=/root/lustre-release \
     KBUILD_EXTRA_SYMBOLS=/root/lustre-release/Module.symvers modules

# baseline (singleton) and the curve; each insmod is one run, results in dmesg
echo 1 > /sys/module/osd_ldiskfs/parameters/lfu_noverify
insmod lfu_par.ko dev=lustre-MDT0000-osd private=0
for n in 1 2 4 8; do insmod lfu_par.ko dev=lustre-MDT0000-osd nthreads=$n chunk=65536; done
dmesg | grep 'lfu_par: dev='
```

Check `objects`, `attr_ok` and `fidsum` are identical across every line
before reading the rates.  For the plateau, `perf record -a -g` around the
best-`nthreads` insmod, and compare the top symbols against the single-thread
profile in `scrub-decomposition-2026-08-07.md`.
