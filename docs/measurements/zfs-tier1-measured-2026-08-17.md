# Tier 1 on a Live ZFS MDT — Built and Run

**Date:** 2026-08-17 (evening; the filter pushdown lab of the same morning is
[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md))
**Lab scripts:** [`tests/lab-zfs/`](../../tests/lab-zfs)
**Raw data:** [`bench-data/2026-08-17/zfs-tier1.txt`](../../bench-data/2026-08-17/zfs-tier1.txt)

Until this run, a filter needing `trusted.som`, `trusted.lov`, `trusted.lmv` or
`trusted.link` was **refused at start-up** on a mounted ZFS target: osd-zfs
answered `rec(DORA_XATTR)` with `-EOPNOTSUPP`, so `INFO` advertised no tier 1
and `lfind-kmdt` declined the query rather than answer it from nothing. This
run builds and exercises the code that closes that.

**The mechanism, in one sentence:** osd-zfs's iterator already unpacks each
object's whole `SA_ZPL_DXATTR` nvlist to find the LMA — that is how it gets the
FID at all — so keeping that nvlist one call longer turns a tier-1 read into a
lookup in memory, with no I/O and no second dnode hold.

---

## 1. The lab

| | |
|---|---|
| Instance | GCP `lfu-zfs-tier1`, `c3-standard-8`, 120 GB pd-balanced, **`us-east1-b`** (all four `us-central1` zones were out of `c3` capacity) |
| OS | Rocky Linux 9.8, kernel `5.14.0-687.36.1.el9_8` |
| OpenZFS | 2.2.10, DKMS |
| Lustre | `v2_17_55` + the six-patch LFU stack, `--enable-server --with-zfs --disable-ldiskfs` |
| Filesystem | `lfufs`: MGS+MDT+2 OSTs+client, three loopback zpools, one node |
| MDT dataset | `lfu-mdt/mdt0`, `xattr=sa`, `dnodesize=auto`, `recordsize=128K`, `compression=off` |
| Namespace | 100,112 objects: 100k `createmany -m` plus one object per shape a tier-1 predicate needs |

Build: 95 s, and `osd_otable_it_xattr`, `osd_otable_it_attr` and
`__osd_xattr_load_by_oid_keep` all present in `osd_zfs.ko`, no warnings from the
new hunks.

## 2. What the module now says it can do

```
kernel side : lfufs-MDT0000-osd, wire v2, private iterator, tier 1: som lov lmv link
```

That line read `tier 1: none` before this change, and every tier-1 row below was
a start-up refusal. Note also *private iterator*, not *private (block parse)* —
`DOIF_PARALLEL` works on osd-zfs, but block parsing is an ldiskfs mechanism and
the header no longer claims it on the wrong backend.

## 3. Every predicate, on a mounted and serving MDT

100,112 objects scanned per row; `emitted` is what the filter selected.

| filter | emitted | xattr reads | expected |
|---|---:|---|---|
| *(none)* | 100,018 | — | baseline |
| `--type f` | 100,011 | — | ✓ |
| `--type d` | 7 | — | ✓ |
| `--projid 1999` | 1 | — | `proj1` ✓ |
| `--attrs i` | 1 | — | `immut1` ✓ |
| `--uid 0` | 6 | — | ✓ |
| `--links +1` | 8 | — | ✓ |
| `--dev-blocks +1G` | **0** | — | **✓ — see §4** |
| `--blocks +1G` (SOM) | **1** | `inline=19` | `big1` ✓ |
| `--size +1G` (SOM) | 1 | `inline=19` | `big1` ✓ |
| `--stripe-count 2` | 2 | `inline=9` | `big1`, `striped1` ✓ |
| `--stripe-count +1` | 3 | `inline=9` | + `wide1` ✓ |
| `--pool fast` | 1 | `inline=9` | `pooled1` ✓ |
| `--ost 1` | 5 | `inline=9` | ✓ |
| `--name 'named*'` | 1 | `inline=100015` | `named1` ✓ |
| `--comp-count +1` | 0 | `inline=9` | no PFL ✓ |
| `--mdt-count +1` (LMV) | 0 | — | single MDT ✓ |
| `-u --size +0` | 16 | `inline=19` | exactly the objects carrying a SOM ✓ |

`--blocks +1G` returned `[0x200000401:0x2:0x0] size=1610612736`, which is the
client's `lfs path2fid` and `stat` byte for byte.

## 4. The size trap, reproduced on ZFS

`--dev-blocks +1G` selected **0** objects where `--blocks +1G` selected 1, on the
same namespace in the same run. The metadata object's own footprint is not the
file's size; only `trusted.som` carries the whole-file number. This is
[`filter-levels.md`](../filter-levels.md) §4 on a second backend, and it is the
same distinction LU-20591's 68020 filter gets wrong on an MDT
([`xiong-68020-filter-measured-2026-08-17.md`](../upstream/xiong-68020-filter-measured-2026-08-17.md) §2).

## 5. The two evaluators agree — 14 of 14, as FID sets

The sequencing is forced and is why this is one script: the kernel scanner needs
the target **mounted**, the userspace ZFS scanner needs the pool **exported**.
So every filter ran through `lfu_ring.ko` on the live MDT, the filesystem came
down, the pool was exported, and the same filters ran through `lfind-zfs`.

| filter | objects | | filter | objects |
|---|---:|---|---|---:|
| `--blocks +1G` | 1 | | `--attrs i` | 1 |
| `--size +1G` | 1 | | `--name named*` | 1 |
| `--size +1M` | 1 | | `--comp-count +1` | 0 |
| `--stripe-count 2` | 2 | | `--type d` | 7 |
| `--stripe-count +1` | 3 | | `--type f` | **100,011** |
| `--pool fast` | 1 | | `--uid 0` | 6 |
| `--projid 1999` | 1 | | `--dev-blocks +1G` | 0 |

**agree = 14, differ = 0.** FID *sets*, not counts — a 100,011-element set among
them. One evaluator source compiled two ways cannot disagree by construction;
this is the second backend on which it demonstrably does not.

## 6. Tier 1 costs per object that *has* the attribute

`--blocks +1G` did **19 xattr reads across 100,112 objects**. The other 100,093
cost nothing at all: "not in the SA nvlist, and no xattr directory" is a
definite `-ENODATA` decided from data already in hand. `--name` did 100,015
reads on the same namespace, because every file has a linkea.

That is the ldiskfs finding reproduced on ZFS — the cost of a tier-1 predicate
scales with **how many objects carry the attribute**, not with the object count.

## 7. Tier 2 is unreachable in practice on osd-zfs

The code has a fallback: an attribute too large for the SA area lives in the
object's xattr directory, reached with a ZAP lookup, a dnode hold and a
`dmu_read()` through `__osd_xattr_get_large()`. **`external=0` on every row
above**, and that is not an accident of this namespace.

`zdb` on an object deliberately padded with a 65,400-byte foreign xattr:

```
196725    1   128K     4K      0      1K     4K    0.00  ZFS plain file
	xattr	200444
	SA xattrs: 424 bytes, 6 entries
		trusted.lma, trusted.lov, trusted.link, trusted.som,
		trusted.version, security.selinux
```

**The 65 KB pad was evicted to the xattr directory; all four filter-relevant
attributes stayed in the 424-byte SA nvlist.** Lustre's `__osd_sa_xattr_set()`
checks the *total* nvlist against `DXATTR_MAX_SA_SIZE` (64 KB) and moves the
attribute *being set*, so the small ones are never the ones displaced. And they
are small by construction: SOM is 24 bytes, LMV is small, linkea is capped at
`MAX_LINKEA_SIZE`, and LOV is bounded by `LOV_MAX_STRIPE_COUNT` = 2000 stripes
(a 1500-stripe file measured 36,032 bytes — comfortably inside the budget, and
served `inline`).

So on osd-zfs the tier-1/tier-2 cliff of [`filter-levels.md`](../filter-levels.md)
§6 does not merely flatten; for the attributes a filter reads it **does not
exist**. Two honest consequences:

- The fallback's *success* path is **unexercised**. Its call path is not: an
  object that has an xattr directory but no LMV forces exactly one real ZAP
  lookup, and `--mdt-count +1` ran that over the whole namespace with `err=0`,
  no crash and an unchanged rate — which retires the real risk in it, holding a
  dnode from inside the iterator.
- A failed directory lookup costs I/O and is **not counted**, because the
  counters only advance on a value actually returned. On this backend that
  undercount is bounded by the number of objects carrying a large foreign
  xattr, which is normally zero.

## 7a. What it costs: 100,015 xattr reads for 1.6%

Warm, one enumerator, medians of three; run-to-run spread inside each row is
under 1%. The ldiskfs column is the same measurement from the morning lab
([`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md))
and is there for the *shape* of the change, not for a rate comparison — the two
backends are 21x apart in absolute enumeration cost.

| configuration | ZFS obj/s | vs no filter | ldiskfs, same predicate |
|---|---:|---|---|
| no filter | 170,141 | — | — |
| `--uid 4242` — tier 0, rejects everything | **171,145** | **+0.6%** | +8.3% |
| `--type f` — tier 0, matches everything | 170,030 | −0.1% | −0.4% |
| `--blocks +1G` — tier 1, 19 SOM reads | 167,367 | −1.6% | −22.6% |
| `--name 'zzz*'` — tier 1, 100,015 linkea reads | 167,459 | **−1.6%** | −26.6% |

Two things the ZFS column says that the ldiskfs one does not.

**Tier 1 is nearly free, and now there is a number for it.** A predicate that
reads an xattr for *every object in the namespace* costs 1.6%. The same
predicate on ldiskfs costs 27%, because there the value has to be found in the
inode's xattr area per object; here it is a lookup in an nvlist the iterator has
already unpacked to get the FID. §6 of [`filter-levels.md`](../filter-levels.md)
predicted this from the on-disk layout; this measures it.

**Rejecting early wins much less here (+0.6% against ldiskfs's +8.3%)**, and for
a reason worth stating rather than hiding: at 170k obj/s the per-object cost of
*enumeration* — a dnode hold, a bonus buffer, an SA unpack — dwarfs the ring
write that a rejected object avoids. On ldiskfs, where enumeration costs 21x
less per object, not writing the record is a much larger share of the total.
Pushdown is still never worse than shipping every record out; it is simply worth
less on the backend that has more expensive objects.

**One caveat on the absolute numbers.** An earlier single run of the same
unfiltered scan, before §5 exported and re-imported the pool, measured ~261k
obj/s against the 170k measured after. Every row in the table above was taken
back-to-back under identical conditions and is comparable within the table;
figures from different phases of this lab are not comparable to each other, in
the same way rates from different labs are not.

## 7b. And it does not break anything upstream expects

This run tested the feature added. A companion run tested the code *touched* —
`osd-zfs/osd_scrub.c` is the scrub's own file, and the patch refactors
`__osd_xattr_load_by_oid()`, which the normal scrub path calls for every object:
[`zfs-suite-regression-2026-08-17.md`](zfs-suite-regression-2026-08-17.md).
`sanity-scrub` 16/0, a `sanity` subset 128/4, `conf-sanity` 22/0 — **identical on
patched and clean v2_17_55**, kernel log clean on both, and the four `sanity`
failures traced to a 0700 home directory rather than to Lustre.

## 8. What this does not measure

- **Cold.** Every row is warm. `c3-standard-8` has no local SSD, so cold here
  would be bandwidth-bound at ~180 MB/s and say nothing about a real MDT
  ([`warm-readahead-and-cold-2026-08-17.md`](warm-readahead-and-cold-2026-08-17.md)).
- **Parallel enumeration into one ring.** One producer thread, as on ldiskfs.
- **A striped-directory LMV shape.** Single-MDT lab, so `--mdt-count` and
  friends are exercised as "no LMV" only.
- **PFL/FLR layouts.** No composite file in this namespace, so `--comp-count`
  and `--mirror-count` are exercised as zero.
