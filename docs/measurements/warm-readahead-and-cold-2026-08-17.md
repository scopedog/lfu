# Warm Readahead Costs, and Cold the Filter Is Free

**Date:** 2026-08-17
**Harness:** [`tests/bench_osd_sweep.sh`](../../tests/bench_osd_sweep.sh) (first real run)
**Raw data:** [`bench-data/2026-08-17/warm-ra-and-cold.txt`](../../bench-data/2026-08-17/warm-ra-and-cold.txt)

Two open questions, one lab session. `open-questions.md` asked *"Does readahead
cost anything warm?"* — the warm curve of
[`blockparse-2026-08-16.md`](blockparse-2026-08-16.md) §3 was taken entirely at
`lfu_ra_blocks=32` and that axis had never been swept. And
[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md)
§8 left cold unmeasured for the filtered scan.

Same lab as that document: GCP c3-standard-8, Rocky 9.8, kernel
`5.14.0-687.36.1.el9_8`, Lustre v2_17_55 + the six-patch stack, MDT on a 20 GiB
loop file with 1024-byte inodes, **302,122 objects**. All 28 sweep rows agree on
`objects=302122 fidsum=8eaa920fb878ae8b attrsum=758a31a8e2ec0915`, so nothing
below is comparing different object sets.

---

## 1. Warm: readahead costs, monotonically, and worse with threads

Medians of three. `bp=1` is the block parse, `bp=0` the iget path.

| `lfu_ra_blocks` | bp=1, j1 | bp=1, j4 | bp=0, j1 | bp=0, j4 |
|---|---|---|---|---|
| **0** (off) | **5,209,000** | **15,106,100** | 1,319,310 | 1,912,164 |
| 8 | 4,720,656 | 13,732,818 | 1,336,823 | 1,876,534 |
| 16 | 4,255,239 | 8,392,277 | 1,307,887 | 1,864,950 |
| **32** (the default, and what every published warm row used) | 4,255,239 | 7,950,578 | 1,296,660 | 1,864,950 |
| 64 | 4,196,138 | 7,368,829 | 1,285,625 | 1,842,207 |
| 128 | 4,028,293 | 6,567,869 | 1,264,108 | 1,798,345 |
| 256 | 3,824,329 | 5,493,127 | 1,233,151 | 1,726,411 |

**Turning readahead off is worth +22% at one thread and +90% at four.** The
suspicion in `blockparse-2026-08-16.md` §3 — that warm every `sb_breadahead()`
is a buffer-cache lookup which finds what it wants and accomplishes nothing,
while taking the same lock as the `sb_bread()` it precedes — is confirmed, and
the thread scaling is the tell: more enumerators means more concurrent lookups
on the same shared structure, and readahead doubles the count.

**The `bp=0` control behaves as predicted.** It declines only ~7% across the
whole range, because `__ldiskfs_get_inode_loc()` issues its own 32-block window
regardless and the path is dominated by `inode_hash_lock` anyway — our window
adds lookups to something already four times slower, and the cost disappears
into it. That asymmetry is itself evidence the warm `bp=1` effect is real and
located where we think it is.

So the published warm figures were **understated**, and by more at higher thread
counts. This document does not restate the 10.4× headline: these rates are from a
different box and are 1.6× below the 2026-08-16 lab's at the same settings
(4.26M vs 6.87M at `ra=32, j1`), which is the known and still-unexplained
cross-lab warm gap. What is comparable is everything *within* this table.

## 2. Cold: the device is saturated, so nothing else matters

Ritual as documented: unmount everything → `drop_caches` → remount → first pass
only. One full cycle per row.

| configuration | obj/s |
|---|---|
| `lfu_par` bp=1 ra=0 j1 | 190,133 |
| `lfu_par` bp=1 ra=32 j1 | 190,255 |
| `lfu_par` bp=1 ra=256 j1 | 189,423 |
| `lfu_par` bp=1 ra=0 j4 | 190,140 |
| `lfu_par` bp=1 ra=256 j4 | 188,718 |
| `lfu_par` bp=0 ra=32 j1 | 190,385 |

Flat within 0.9% across block parse vs iget, every readahead window, and one vs
four threads. That is not a scanner result — **it is the disk**:

```
raw sequential read, backing block device, O_DIRECT : 183 MB/s
302,122 objects x 1 KiB inodes                     : ~302 MB
190,000 obj/s                                      : ~190 MB/s
```

The cold scan is running at **~100% of a GCP pd-balanced disk**, so there is no
headroom for anything to exploit or waste. This reproduces the shape of
`parallel-osd-measured-2026-08-15.md`'s cold rows ("flat within 0.7% at every
thread count") for the same reason.

**It therefore does not answer the cold readahead question**, and must not be
read as contradicting `blockparse-2026-08-16.md` §4, where cold on local NVMe was
*latency*-bound at queue depth 1 and readahead was worth 8×. Bandwidth-saturated
and latency-bound are different regimes; this instance type has no local SSD, so
only the first is reachable here. The 08-16 result stands.

## 3. Cold, the filter is free — the inverse of warm

| filter | obj/s | xattr lookups |
|---|---|---|
| no filter | 183,299 | — |
| `--uid 4242` (tier 0, rejects everything) | 190,442 | `inline=0 external=0` |
| `--blocks +1G` (tier 1) | 190,458 | `inline=4021 external=1` |
| `--name 'zzz*'` (tier 1, every object has a linkea) | 190,387 | `inline=302018` |

`--name` performs **302,018 xattr lookups and costs nothing** — it is if anything
faster than no filter at all. Warm, the same predicate cost 27%.

The reason is the one the tier model is built on, seen from the other side: a
tier-1 xattr lives in the same inode-table block the attributes came from, and
cold that block is already being paid for. Tier 1 is a *CPU* cost, not an I/O
cost, so it is visible exactly when the scan is CPU-bound and invisible when it
is device-bound. Combined with §1, the picture is:

| regime | tier-0 reject | tier-1 predicate | readahead |
|---|---|---|---|
| **warm** (CPU-bound) | **+8%** (never enters the ring) | −13% to −27% | **−22% to −90%** |
| **cold, bandwidth-saturated** | +4% | **free** | irrelevant |
| **cold, latency-bound** (08-16, NVMe) | untested | untested | **+8×** |

## 4. What this changes

**`lfu_ra_blocks=32` is the wrong default in two of three regimes.** It costs up
to 90% warm, is irrelevant when the device is saturated, and is worth 8× only
when cold *and* latency-bound. A static default cannot be right; the window wants
to be adaptive, and the cheapest signal available is what the scan is already
measuring — if `sb_bread()` is hitting the buffer cache, the window is pure
overhead. That is a design change, not a tuning change, and it is now sized:
worth up to 90% of the warm rate.

**Filter pushdown is free or better in every regime measured.** +8% warm, +4%
cold, and cold the tier-1 read costs nothing at all. There is no regime in this
data where evaluating the filter in the kernel is worse than shipping every
record to userspace.

**What is still unmeasured:** cold on latency-bound storage with a filter set
(needs local NVMe, i.e. a different instance type); parallel enumeration into one
ring; and ZFS tier 1, which `rec(DORA_XATTR)` refuses by design.
