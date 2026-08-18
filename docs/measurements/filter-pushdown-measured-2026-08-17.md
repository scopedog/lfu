# Filter Pushdown, Measured: the Kernel Side Built and Run

**Date:** 2026-08-17
**Patches:** the six-patch stack through
[`patches/otable-xattr-v2_17_55.patch`](../../patches/otable-xattr-v2_17_55.patch)
**Module:** [`src/kernel/lfu_ring.c`](../../src/kernel/lfu_ring.c) ·
**Consumer:** [`src/lfu_scan_kmdt.c`](../../src/lfu_scan_kmdt.c)
**Raw data:** [`bench-data/2026-08-17/filter-pushdown-lab.txt`](../../bench-data/2026-08-17/filter-pushdown-lab.txt)

[`filter-levels.md`](../filter-levels.md) §5.4 shipped the OSD-side filter with one
row of its verification table empty: *"`lfu_ring.c` and `osd_otable_it_xattr()`
compile and run — not done."* This fills it in.

**Lab.** One throwaway GCP c3-standard-8 (8 vCPU), Rocky 9.8, kernel
`5.14.0-687.36.1.el9_8`, Lustre **v2_17_55 source build** with the whole stack,
single node carrying MGS + MDT0 + four OSTs + the client. MDT on a 20 GiB loop
file with **1024-byte inodes** — the size `mkfs.lustre` picks, and the reason
LMA, LOV and SOM are normally inline. **302,122 objects.** Instance *stopped*
rather than deleted after the run, so the lab can be restarted for the cold-on-NVMe
and parallel-ring measurements §8 still lists; the recipe to rebuild it from
nothing is in `notes/reference/build_install.md` §3.4 as corrected here.

---

## 1. It builds

All six patches applied to a clean `v2_17_55` with `git apply`, in order.
`ENABLE_LDISKFS='yes'` (checked out of `config.log`, never inferred from
configure's exit status), 105 s to build on 8 cores, and every new symbol is in
the module:

```
present  osd_raw_xattr        present  osd_iit_iget_raw    present  lfu_blockparse
present  osd_raw_attr         present  osd_otable_it_xattr present  lfu_ra_blocks
```

`lfu_ring.ko` built with **no warnings** and carries the evaluator —
`lfu_filter_tier0`, `lfu_filter_tier1`, `lfu_ea_decode`,
`lfu_filter_validate` — which is the first direct evidence that one source
really does compile for both userspace and kernel. `CONFIG_GLOB=y`, so
`glob_match()` is there for `--name` and `--pool`.

Two corrections to [`notes/reference/build_install.md`](../../../notes/reference/build_install.md)
fell out of this: **every `downloads.lustre.software` path in §3.1 now 404s**,
including the GPG key, so the Lustre-patched e2fsprogs has to come from
`downloads.whamcloud.com/public/e2fsprogs/latest/el9/` (1.47.3-wc2); and
`mkfs.lustre` on a loop-backed file **requires `--device-size=`** and will not
infer it.

## 2. It runs, and says what it is

```
kernel side  : testfs-MDT0000-osd, wire v2, private (block parse) iterator,
               tier 1: som lov lmv link
```

That line is `LFU_RING_IOC_INFO` answering before a single record is trusted.
No `BUG`, `WARN` or `Call Trace` in `dmesg` across every run in this document.

## 3. The size trap, reproduced on a real MDT at last

§4.3 predicted this from `mdt_handler.c` on 2026-08-16 and could not reproduce
it; §10 has carried it as open ever since. `big1` is a 1.5 GiB file striped
over 4 OSTs:

| filter | objects found |
|---|---|
| `--dev-blocks +1G` — the MDT inode's own `i_blocks` | **0** |
| `--blocks +1G` — the file's, from `trusted.som` | **1** |
| `--size +1G` | **1** |

```
[0x200000401:0x7:0x0] ino=11001992 f mode=0644 nlink=1 uid=0 gid=0 projid=0
  size=1610612736 blocks=3129344 atime=1786980058 mtime=1786980059
  stripes=4 ssize=4194304
```

`lfs path2fid` on the file returns `[0x200000401:0x7:0x0]` and `stat` returns
`size=1610612736`: the FID and the size both match exactly. **The old `-b`
semantics really did match nothing on a real MDT, and the SOM path really does
answer.** That closes the §10 item.

One detail worth recording rather than smoothing over: SOM reports
`blocks=3129344` where the client's glimpsed `stat -c %b` says `3145728`, a 0.5%
difference. That is lazy SOM being lazy — the value written at close, which is
what `lfs find --lazy` would also report. It is the documented semantic, not an
error, and it is the reason §4.4 insists an MDT-only size answer be labelled as
such.

**SOM is on by default in 2.17.** There is no `mdt.*.enable_som` parameter any
more and every closed file carried `trusted.som`, so the *undecided* population
on this filesystem was **0** — `-u --size +0` found none. §4.4's third outcome
is still right in principle (a file open for write has no SOM yet), but on a
modern MDT it is rare, which is better news for the largest-files use case than
§4 assumed.

## 4. Every predicate agrees with the userspace scanner

The same filter through the kernel (Option 2, pushed down) and through
`lfind-ldiskfs` reading the same loop file read-only while mounted (Option
1). FID sets compared, not counts:

| filter | verdict | objects |
|---|---|---|
| `--blocks +1G` | AGREE | 1 |
| `--size +1G` | AGREE | 1 |
| `--stripe-count 4` | AGREE | 2 |
| `--pool fast` | AGREE | 1 |
| `--projid 1999` | AGREE | 1 |
| `--attrs i` | AGREE | 1 |
| `--layout mdt` (DoM) | AGREE | 1 |
| `--name 'report*'` | AGREE | 1 |
| `--name second_link.txt` | AGREE | 1 |
| `--comp-count +1` | AGREE | 1 |
| `--type d` | AGREE | 8 |
| `--dev-blocks +1G` | AGREE | 0 |

`--projid` and `--attrs` are the two that could not have worked yesterday: they
need `la_projid` and `la_flags`, which §5.1 recorded as missing from both OSD
read paths. `--name second_link.txt` matching the *second* linkea entry is the
byte-order correction from `53cbbe6` proving itself on a linkea the MDT wrote.

## 5. Tier 2 fired exactly once, and was counted

`over60` is overstriped 60 ways; its `trusted.lov` cannot fit a 1 KiB inode, so
ext4 spills it:

```
[0x200000401:0x9:0x0] ino=11001993 f ... stripes=60 ssize=4194304 +extea
kernel: ... xattr: inline=4021 external=1 iget=0 toolarge=0 err=0
```

`external=1` out of 302,122 objects. The in-inode lookup declined, the raw
inode's `i_file_acl` was set, `rec(DORA_XATTR)` took the iget path, and the
answer was still right (`stripes=60`). The tier-1/tier-2 boundary works in both
directions and the rate is now a number rather than an inference.

## 6. Rates — and what tier 1 actually costs

Medians of three, warm, one enumerator thread, 302,122 objects.

| filter | obj/s | vs no filter | xattr lookups served |
|---|---|---|---|
| no filter | 3,587,401 | — | — |
| `--type f` (tier 0, matches ~all) | 3,572,170 | −0.4% | `inline=0` |
| `--uid 4242` (tier 0, matches 0) | **3,884,601** | **+8.3%** | `inline=0` |
| `--mtime +365d` (tier 0, matches 0) | **3,896,108** | **+8.6%** | `inline=0` |
| `--stripe-count +1` (tier 1) | 3,128,778 | −12.8% | `inline=302018`* |
| `--blocks +1G` (tier 1) | 2,775,551 | −22.6% | `inline=4021` |
| `--name 'zzz*'` (tier 1) | 2,632,343 | −26.6% | `inline=302018` |
| `--type f --blocks +1G` | 2,767,194 | −22.9% | `inline=4021` |

Three things worth taking from this.

**A rejecting tier-0 filter is faster than no filter at all** — 3.88M against
3.59M, +8%. That is pushdown paying for itself, and it is worth being precise
about where the 8% comes from, because "filtering makes it faster" sounds
backwards.

Up to the filter, the producer loop
([`lfu_ring.c`](../../src/kernel/lfu_ring.c) §`lfu_ring_producer`) does the same
work per object either way: `iops->rec(..., DORA_ATTR)` — the attributes are
read regardless, block parsing has the raw inode in hand anyway —
`lfu_rec_from_dor()` to fill the record, then `lfu_filter_tier0()`, which for
`--uid 4242` is one integer compare on a field already loaded and touches no
xattr area at all.

Then the paths diverge, and only the *matching* one pays:

- the ring-space check, and a stall if the consumer is behind
- `lfu_fill_rec()` into `r->buf[head & (ring_recs - 1)]` — a wide store into
  the ring
- `smp_store_release(&r->head, ...)`, and a `wake_up(&r->wq_cons)` per batch
- downstream, the consumer's `read()` → `copy_to_user()` for all 302,122
  records and the userspace record handling, on the same 8 vCPUs

`--uid 4242` matches nothing, so all of that disappears for the whole scan.

Two things in the data pin the explanation down rather than leaving it a story.
**`--type f` is the control**: the same tier-0 evaluator, matching ~everything,
costs −0.4%. So evaluation itself is free to within the noise, and the +8% is
entirely the emit path not being taken. And **`stalls=0` on every run**, so it
is not the producer blocking on a full ring — it is the per-record store, the
`copy_to_user`, the consumer's CPU, and the ring cachelines bouncing between
the producer kthread and the reader.

That also predicts the shape of the win: it scales with selectivity. A tier-0
filter rejecting half the objects should land near +4%, and one that matches
everything near 0 — which is exactly what `--type f` does. The premise of
design-osd-scanner.md §4 ("the ring is the scarce resource") is now measured
rather than asserted.

**A pure tier-0 query never opens the xattr area.** `inline=0 external=0
iget=0` on every tier-0 row. The demand mask does exactly what §9 asked for.

**The cost of a tier-1 predicate scales with how many objects *have* the
attribute, not with the object count.** `--blocks +1G` did 4,021 lookups over
302,122 objects and cost 23%; `--name` did 302,018 and cost 27%. The 300,000
`createmany -m` objects have no SOM and no LOV, and "not in the inode and no
external block" is a free, definite `-ENODATA` — so they cost nothing, while
almost all of them have a linkea and so all of them pay for `--name`. This
refines the tier model usefully: **tier 1 is not a per-query cost, it is a cost
per object that carries the attribute.** A `--name` scan on a real MDT should be
expected to pay everywhere; a `--size` scan pays only for files that have been
closed.

Ordering only helps when the tier-0 predicate is *selective*: `--type f
--blocks +1G` costs the same as `--blocks +1G` alone, because `--type f` rejects
almost nothing here.

\* `--stripe-count +1`'s counter is from a separate pass and reflects LOV only.

## 7. Two bugs the lab found

Both in reporting/control, neither in the filter logic, and both fixed:

- **`--limit` did not stop mid-batch.** `lfu_kmdt_scan_chunk()`'s inner loop
  processed a whole 8192-record batch after `cx->stop` was set, so `-n 5`
  printed everything the first `read()` returned. The other two backends check
  `cx->stop` per object; this one did not.
- **The rate line divided survivors by wall time.** With the filter pushed down,
  userspace `st->seen` counts records that *arrived*, so `--blocks +1G` reported
  "9 objects/sec" for a scan that walked 302,122. It now reports the kernel's
  `rs_seen`, and prints `objects scanned` next to it so the two cannot be
  confused again. Every rate in §6 is from the fixed build.

## 8. What is still not measured

- **Cold** — since measured, in
  [`warm-readahead-and-cold-2026-08-17.md`](warm-readahead-and-cold-2026-08-17.md)
  §2-3: on this box cold is bandwidth-bound at ~100% of a 183 MB/s disk, so every
  configuration is flat within 0.9%, and **a tier-1 predicate costs nothing cold**
  because its xattr rides in a block already being read. What is still missing is
  cold on *latency-bound* storage (local NVMe) with a filter set, which needs a
  different instance type.
- **Parallel enumeration into one ring.** The producer is a single thread. The
  2.03M→17.4M warm scaling of `lfu_par` is behind the iterator; feeding N
  private iterators into one ring is the next step and is untested.
- **ZFS.** At the time of this run `rec(DORA_XATTR)` returned `-EOPNOTSUPP` on
  osd-zfs, so `INFO` advertised no tier 1 there and a tier-1 filter was refused.
  Closed later the same day, and **built and run** on its own lab:
  osd-zfs serves it from the SA xattr nvlist its iterator already holds —
  [`zfs-tier1-measured-2026-08-17.md`](zfs-tier1-measured-2026-08-17.md). 14 of
  14 filters agree with `lfind-zfs` on the same data, `--blocks +1G` finds the
  1.5 GiB file where `--dev-blocks +1G` finds nothing, and a tier-1 predicate
  reading an xattr for every object costs 1.6% against ldiskfs's 27%.
- **The `-EAGAIN` fallback rate is 0 here** (`raw=302122 fallback=0`), on a
  filesystem where every object had an inline LMA. A filesystem with pre-2.0
  IGIF objects would exercise it.
