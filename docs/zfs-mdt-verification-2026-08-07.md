# ZFS Scanner — Verification Against a Real osd-zfs MDT

**Date:** 2026-08-07
**Status:** the §14 fidelity gap is closed. Three design assumptions confirmed,
two falsified, one blocker found that no synthetic rig could have surfaced.

Until now `lfu_scan_zfs` had only ever run against a synthetic rig: objects
created through the ZPL with hand-written `trusted.lma` xattrs. That exercised
enumeration, SA reads, DXATTR unpacking and classification, but not objects
created by osd-zfs itself. This run closes that gap.

---

## 1. The lab

Single all-in-one node — everything the scanner needs is on the MDT, so a
three-node split would have cost 3× for identical evidence.

| | |
|---|---|
| Instance | GCP `lustre-zfs-lab`, `c3-standard-8`, 100 GB pd-balanced, `us-central1-a` |
| OS | Rocky Linux 9.8, kernel `5.14.0-687.34.1.el9_8` |
| OpenZFS | 2.2.10 (DKMS), userland and kmod at the same version |
| Lustre | `v2_17_55` from source, `--enable-server --with-zfs --disable-ldiskfs` |
| Filesystem | `llmount.sh` with `FSTYPE=zfs`: MGS+MDT+OST+client, loopback zpools |
| MDT dataset | `lustre-mdt1/mdt1`, `dnodesize=auto`, `xattr=sa`, `recordsize=128K`, `compression=off` |

Two build notes worth keeping:

- **There are no prebuilt osd-zfs server packages.** The
  `lustre-b2_17-server-rocky-9` repo ships `kmod-lustre-osd-ldiskfs` and
  `lustre-osd-ldiskfs-mount`, but for ZFS only `lustre-zfs-dkms` — no
  `lustre-osd-zfs-mount`, so `mkfs.lustre`/`mount -t lustre` on a ZFS target
  cannot work from packages. A source build is the only route.
- **`--with-zfs=<path>` is the wrong flag with DKMS.** Pointing it at
  `/usr/src/zfs-2.2.10` makes configure look for the object dir at
  `<path>/$LINUXRELEASE` and fail. Bare `--with-zfs` autodetects
  `/var/lib/dkms/zfs/$VER/source` + `/var/lib/dkms/zfs/$VER/$LINUXRELEASE/$ARCH`
  correctly. As always, `grep ENABLE_ZFS= config.log` — configure exits 0
  either way.
- Run the test-suite scripts with **`bash`, not `sh`**. `stack_trap()` in
  `test-framework.sh` parses `trap -p` output and breaks in POSIX mode
  (`unexpected EOF while looking for matching "'"` at line 7427).

---

## 2. The blocker: a real Lustre pool cannot be opened at all

The prototype could not read the MDT. Two independent reasons, both invisible
on the synthetic rig, both now fixed in `lfu_scan_zfs.c`:

**1. Lustre creates its pools with `cachefile=none`.** `kernel_init()` loads
pool configuration from `/etc/zfs/zpool.cache`; a Lustre pool is never in it
(HA failover must not depend on a stale cache). `dmu_objset_own()` returned
`ENOENT`. The pool has to be located by reading vdev labels, as `zpool import`
and `zdb -e` do.

**2. Lustre sets `multihost=on`.** libzpool has no hostid of its own, and
`spa_ld_check_features()` refuses a multihost pool to a zero-hostid caller with
`EREMOTEIO` unless `ZFS_IMPORT_SKIP_MMP` is set. Note this fires even on a
cleanly *exported* pool — the label state was `EXPORTED` and the import was
still refused.

The synthetic rig hit neither: a hand-made test pool has the default cachefile
and `multihost=off`.

**Fix:** `-e/--import` finds the pool by scanning devices (`-p DIR`, repeatable,
default `/dev`) via `zpool_find_config()` + `spa_import()`, both exported from
`libzpool.so`. MMP is skipped unconditionally — the scanner holds the pool
read-only (`SPA_MODE_READ`), and MMP exists to stop a second *writer*; this is
what `zdb -e` does. Because that discards ZFS's own "someone else has this
pool" guard, the scanner makes the check itself from the label and refuses a
pool whose state is `ACTIVE` unless `--force-active` is given.

The operational consequence is worth stating plainly: **the userspace scanner
requires the pool to be exported**, i.e. the target unmounted. That is
consistent with what Option 1 is for (offline analysis of an unmounted MDT or a
snapshot) but it is not a "scan a live MDT" tool, and `--force-active` only
relaxes the check, not the physics — a forced read sees what reached disk.

---

## 3. Correctness: the `lfs find` oracle

Tree: 1004 files, 22 directories, 1 symlink, 1 FIFO, 1 hardlink, sizes 1 B–1 MiB.
Oracle: `lfs path2fid` over every path, 1027 distinct FIDs (the hardlink pair
shares one). Snapshot taken while mounted, then unmount → export → scan.

```
scan complete in 0.02s (snapshot: txg-consistent)
  dnodes seen   : 1356      not znodes : 5        sa_fail : 0
  visible       : 1032      internal   : 89       no-lma  : 230
```

- **In the oracle but missed by the scanner: 0.** Every namespace FID was found.
- **Found but not in the oracle: 5** — `/` (`[0x200000007:0x1:0x0]`),
  `.lustre`, `.lustre/fid`, `.lustre/lost+found`, and one more, below.
- `sa_fail = 0`, and repeat scans of the snapshot are bit-identical.

### 3.1 One false positive in `visible`

`[0x200000400:0x1:0x0]` (dnode 896) classifies as `visible` but `lfs fid2path`
returns `No data available`. zdb shows a zero-length plain file created at
format time, `links=1`, parent dnode 10 (an OSD-internal directory), carrying
only `trusted.lma` with `lma_compat = 0` — so no `LMAC_NOT_IN_OI` flag to
exclude it by, and a normal-sequence FID (`FID_SEQ_NORMAL = 0x200000400`) that
the ladder is right to treat as namespace-visible.

It is one object, created at format, and it does **not** scale: still exactly
one at 301,033 visible objects. Low impact, but it means "visible" is not
identical to "has a path", and any consumer joining against a path must
tolerate a miss.

---

## 4. What the real MDT falsified

### 4.1 §5's conjecture — internal objects do *not* fall out for free

The design conjectured that ZFS-internal objects are excluded by
`doi_bonus_type != DMU_OT_SA` with no denylist. On pool-level objects that
holds — only 5 dnodes were rejected that way.

But **230 dnodes (17% of a fresh MDT) are osd-zfs's own directory hierarchy**:
ZAP directories, `mode 40755`, `size 0`, `links 0`, all parented to dnode 34,
all created at format time, all with a 152-byte SA bonus and **no xattrs at
all** — hence no LMA. They pass the bonus-type gate and land in `no-lma`.

Consequences:

- **The ladder is still correct** — `no-lma` is not `visible`, so nothing leaks
  into results. The classification outcome is right; the design's *reason* for
  it was wrong.
- **"no-LMA implies suspicious" is false on osd-zfs.** A healthy, freshly
  formatted MDT has hundreds of legitimately LMA-less objects. Any health
  reporting built on the `no-lma` counter would fire on every ZFS target. This
  is a real difference from ldiskfs and needs to be stated wherever `no-lma` is
  interpreted.
- The count is fixed at format time (230 at 1.3k objects and at 301k), so it is
  a constant, not a proportion — it just dominates when the MDT is nearly empty.

### 4.2 `links == 0` does not mean "pending delete"

`unlinked` counted 231 — 230 of them are the internal directories above, which
are live and reachable but carry `links = 0` because osd-zfs does not maintain
ZPL link counts for its own hierarchy. The stat as documented ("on the delete
queue") is wrong on osd-zfs.

---

## 5. What the real MDT confirmed

### 5.1 §4.4 — attributes are inline, and cheap

This was flagged **[unverified, load-bearing]**: the whole performance model
assumes `dnodesize=auto` keeps SA attributes *and* the Lustre xattrs in the
dnode bonus buffer, so one dnode read gets everything.

Confirmed, with room to spare. Over all 1351 SA-bonus objects:

| dnode size | count |
|---|---|
| 1 KiB | 1258 |
| 512 B | 98 |

| bonus used | count | what |
|---|---|---|
| 608 B | 1001 | regular files: SA attrs + LMA + LOV + linkea |
| 152 B | 229 | the osd-zfs internal directories (no xattrs) |
| 228 B | 82 | |
| 464 B | 20 | |
| 272 B | 8 | |
| 468 B | 2 | |
| **636 B** | max observed | |

A 1 KiB dnode provides ~832 bytes of bonus space. The largest bonus seen was
636 B, and **exactly one object out of 1351 carried a `SPILL_BLKPTR`** (0.07%).
So the common case is a single dnode read per object with no spill-block
follow-up — the assumption the performance model rests on.

### 5.2 §4.2 — the SA registry replication is correct

`sa_setup()` against the dataset's own registry produced attribute values that
match `lfs`/`zdb` for every object; `sa_fail = 0` across 301k objects. The
"silent wrong attributes" failure mode this guards against did not occur.

### 5.3 §6.1 — snapshot atomicity holds on a real target

Repeat scans of `lustre-mdt1/mdt1@lfu1` are bit-identical; post-snapshot
mutations are invisible; scanning the live dataset instead prints the warning
and reports a different internal count (88 vs 89) — the open-txg effect §6.2
predicts, observed on a real MDT rather than a rig.

---

## 6. Throughput — first ZFS numbers

300,000 additional zero-length files via `createmany` (7,300 creates/s), then
snapshot → export → scan:

```
301,357 dnodes in 3.78s   =  ~80,000 objects/s   (cold)
301,357 dnodes in 3.71s   =  ~81,000 objects/s   (warm)
```

Context, and the caveats matter:

| Scanner | obj/s | |
|---|---|---|
| ldiskfs userspace scanner | 705,000 | sequential inode-table reads at device bandwidth |
| OI scrub (in-kernel, ldiskfs) | 105,000 | measured 2026-08-06 |
| **ZFS userspace scanner** | **~80,000** | single-threaded, file vdev, pd-balanced |

That was the floor, and it has since been raised to **~274,000 obj/s** — see §6.1.

---

### 6.1 Profile-driven optimisation: 80k → 274k obj/s

The cold/warm runs were within 2% of each other, which says the scan was not
I/O-bound. `perf record` on the 301k scan confirmed it and killed the design's
standing hypothesis:

| symbol | self+children |
|---|---|
| `dmu_object_info` | 26.7% |
| `dnode_hold_impl` | 25.3% |
| `dmu_object_next` | 23.6% |
| `sa_handle_get` | 13.6% |
| `sa_lookup` | 1.5% |
| **`nvlist_unpack`** | **0.0%** |

The per-object DXATTR nvlist unpack — the thing §4.3 flags as the interesting
work, and the first thing anyone would suspect — **costs nothing**. The cost is
the DMU object path: dnode hold, dbuf hash, ARC, and the mutex traffic they
carry. Two changes followed.

**1. One dnode hold per object (~9%).** `dmu_object_info()` and
`sa_handle_get()` each took their own hold of the same dnode. Holding once with
`dnode_hold()` and using `dmu_object_info_from_dnode()` +
`dmu_bonus_hold_by_dnode()` + `sa_handle_get_from_db()` gave 3.76s → 3.44s.
Less than the 40% those two symbols suggested, because the second hold was
already hitting a warm dbuf cache — worth having, not the answer.

**2. §8 parallel object-ID ranges (`-j N`) — the actual multiplier.** Workers
take 64K-object chunks from a shared cursor (chunks, not N equal slices: dnode
allocation is sparse and clustered, so equal slices imbalance badly). A worker
that finds nothing at or beyond its chunk start has proved there is nothing
beyond it at all, since `dmu_object_next()` scans forward globally, so it can
end the hand-out for everyone.

| `-j` | time | obj/s |
|---|---|---|
| 1 | 3.44s | 87,600 |
| 2 | 2.34s | 128,800 |
| 4 | 1.72s | 175,200 |
| 8 | 1.36s | 221,600 |
| 12 | 1.13s | 266,700 |
| 16 | 1.12s | 269,100 |
| 24 | 1.10s | 274,000 |
| 32 | 1.10s | 274,000 |

**3.4× over the single-threaded baseline**, on 8 vCPUs. Output is identical to
`-j 1` at every thread count (sorted comparison) and every counter matches, so
this is a pure throughput change.

Two things worth noting. The knee is past `nproc` — `-j 12` beats `-j 8` — so
workers block rather than spin, and mild oversubscription pays. And the plateau
is a contention ceiling, not a core count: re-profiling at `-j 12` puts
`pthread_mutex_lock`/`unlock` at 18% with `zrl_add_impl`/`zrl_remove` and
`aggsum_add` behind it. That is libzpool's own shared state — dbuf hash, ARC
accounting, dnode handle locks. Going past ~274k obj/s means reducing shared
state (several objsets, or a lighter read path), not adding threads.

**Still not implemented:** §7 route 2's `traverse_dataset()` prefetch. The
cold/warm result argues it has little to offer here, but that was measured on a
file vdev whose backing file was in host page cache; on a real disk-backed MDT
with cold ARC it could matter, and that remains untested.

**Revised comparison** (and it is still not apples to apples — file vdev on
cloud storage):

| Scanner | obj/s |
|---|---|
| ldiskfs userspace scanner | 705,000 |
| **ZFS userspace scanner, `-j 24`** | **274,000** |
| OI scrub (in-kernel, ldiskfs) | 105,000 |
| ZFS userspace scanner, `-j 1` | 87,600 |

The gap to ldiskfs is now ~2.6×, not ~9×, and the ZFS scanner is above
in-kernel OI scrub. The ldiskfs number is itself single-threaded, so the honest
statement is that the two have not been compared at equal parallelism.

---

## 7. Changes made to the scanner

All in `src/lfu_scan_zfs.c` unless noted; `tests/run_tests_zfs.sh` still
passes 16/16.

- `-e/--import`, `-p/--search DIR`, `--force-active` — the device-scanning
  import path of §2, with the ACTIVE-label guard.
- `-v` now dumps one class-tagged line per object regardless of classification.
  This is what made §4.1 findable; there was previously no way to see the
  `no-lma` population.
- Single dnode hold per object via the by-dnode DMU entry points (§6.1).
- `-j/--threads N` — §8 parallel scan over object-ID chunks. Default 1, so the
  existing single-threaded behaviour and record ordering are unchanged;
  `--limit` forces `-j 1` since "stop after N dnodes" has no meaning across
  workers. Record order at `-j >1` is unspecified.
- `Makefile`: `make zfs ZFS_SRC=/usr/src/zfs-<ver>` builds against the ZFS
  source tree. RHEL's `libzfs5-devel` omits the userspace os-specific headers
  (`sys/abd_os.h`), so a libzpool consumer cannot be built from the installed
  headers at all; Ubuntu's `libzfslinux-dev` can, and plain `make zfs` still
  works there.

---

## 8. What is still open

- **OST-side scanning** — this run covered the MDT only.
- **`traverse_dataset()` prefetch** (§7 route 2) — still unimplemented; §6.1
  argues it has little to offer on a page-cache-warm file vdev, untested on a
  cold disk-backed MDT.
- **Past ~274k obj/s** the limit is libzpool's internal lock contention (§6.1),
  which more threads will not fix.
- **linkea/LOV parsing** and Object Stream encoding — output is still text.
- **Blocks semantics** (§12) — this MDT had `compression=off`, so the
  post-compression `doi_physical_blocks_512` divergence from ldiskfs was not
  exercised. Still open.
- **DNE / multiple MDTs**, and **encrypted datasets**.
- Throughput on a real disk-backed vdev, and with more than one thread.
