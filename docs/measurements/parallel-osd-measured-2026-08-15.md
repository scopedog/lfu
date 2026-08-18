# Step 5 Measured — Parallel Enumeration Clears 1M obj/s, Reverses the ZFS Posture, and Ends the LFSCK Conflict

**Date:** 2026-08-15
**Design:** [`parallel-osd-scanner-2026-08-15.md`](../superseded/parallel-osd-scanner-2026-08-15.md)
**Patch:** `patches/parallel-it-v2_17_55.patch` · **Harness:** `src/kernel/lfu_par.c`
**Raw data:** [`bench-data/2026-08-15/`](../../bench-data/2026-08-15)
**Supersedes:** `design-osd-scanner.md` §8.1 (the singleton as a hard ceiling)
and the open item left by `scrub-decomposition-2026-08-07.md` step 2.

> **Superseded in part, 2026-08-16 — read this first.** Every ldiskfs rate in
> this document was bounded by `ldiskfs_iget()`, which §3 correctly identifies as
> the wall and §3's third bullet correctly names the fix for. That fix was built
> the next day: [`blockparse-2026-08-16.md`](blockparse-2026-08-16.md) parses
> inodes straight out of the inode-table blocks on the `DOIF_PARALLEL` path.
> ldiskfs warm goes **1,669,530 → 17,392,147 obj/s (10.4×)** and the curve peaks
> at *four* threads instead of two, because the box goes idle before the lock
> does. Cold goes to **1,420,664 obj/s at 99% of an NVMe stripe** — parity with
> the userspace device scanner, which retires the "userspace still faster warm"
> row in §0 as well.
>
> **The ZFS half of this document stands unchanged** — it does not go through
> `iget`, and the posture reversal in §6a is still the current result.
>
> What is worth keeping here is the reasoning, not the ldiskfs numbers: §3
> diagnosed a single call from a profile and predicted the right lever, and §5
> proved LFSCK coexistence with a control row that still holds.

**Two labs, both backends, both deleted after the runs.** Each a GCP
c3-standard-8 (8 vCPU Xeon 8481C), Rocky 9.8, kernel `5.14.0-687.36.1.el9_8`,
Lustre **v2_17_55 source build** with the patch stack, single node, ~2M objects
from `createmany -m`, `debug=0`, three passes per row, OI verification off on
both sides of every A/B.

- **ldiskfs** (§1–§6): MGS+MDT0 on a 20 GiB loop file — 8,388,608 inodes,
  32,768 per group, 1 KiB inodes — **2,000,097 objects**.
- **ZFS** (§6a): OpenZFS 2.2.10 DKMS, MGS+MDT0 on a 24 GiB file vdev,
  **2,000,333 objects** — the same count the 2026-08-10 ZFS lab produced.

Sections §1–§6 are ldiskfs. §6a is ZFS, and it is where the headline changes.

## 0. Both backends in one table

| | ldiskfs | ZFS |
|---|---|---|
| singleton baseline | 852,921 | 154,459 |
| private, 1 thread | 1,247,723 (1.46×) | 193,713 (1.25×) |
| **best** | **2,028,498 at j2 (2.38×)** | **561,509 at j16 (3.64×)** |
| shape | peaks at 2, plateaus ~1.80M | climbs to 4, saturates the box at 8–16 |
| the wall | one global lock (`inode_hash_lock`, 83% of j8) — **removed 08-16 by block parsing; the new limit is the box going idle** | nothing dominates — distributed DMU hold traffic; the plateau is core count |
| cold | ~173k, flat at every thread count **on a 190 MB/s disk** — see the 08-16 retraction: on NVMe it scales 3.6× (202k → 731k) and is latency-bound, not device-bound | **scales**: 97.8k → 424k at j8 (CPU-bound) |
| attributes under parallelism | free (≤1%) | near-free (2–4%) |
| vs the userspace device scanner | userspace still faster warm (~4M at `-j 4`) — **reversed 08-16: 17.4M in-kernel, and cold parity at 1.01×** | **in-kernel now 2.52× faster** |
| LFSCK coexistence | proven | proven |
| correctness vs singleton | identical FID set + attrs | identical FID set + attrs |

## 1. The answer (ldiskfs)

**Yes — and by more than the target needs.** Two enumerator threads on a
private iterator reach **2.03M objects/sec** against the singleton's 853k on
the same MDT, same boot: **2.4×**, with the 1M obj/s/MDT target cleared even
single-threaded.

| threads | server-only (MDT mounted alone) | vs singleton | full FS mounted (MGS+MDT+OST+client) | vs singleton |
|---|---|---|---|---|
| singleton (`od_otable_it`) | 852,921 | 1.00× | 757,899 | 1.00× |
| private, 1 | 1,247,723 | 1.46× | 1,079,965 | 1.42× |
| **private, 2** | **2,028,498** | **2.38×** | **1,623,455** | **2.14×** |
| private, 3 | 1,836,639 | 2.15× | — | — |
| private, 4 | 1,795,421 | 2.11× | 1,518,676 | 2.00× |
| private, 6 | 1,833,272 | 2.15× | — | — |
| private, 8 | 1,797,035 | 2.11× | 1,518,676 | 2.00× |
| private, 16 | 1,797,035 | 2.11× | 1,514,077 | 2.00× |

Medians of three; run-to-run spread ≤3.2%, mostly ≤1.5%.

Three things in that table beyond the headline:

1. **One private thread already beats the singleton by ~1.45×** (1.25M vs
   853k). That is not parallelism — it is the cost of the couplings the
   private path drops: the 64-entry preload cache handed between producer and
   consumer, the scrub thread's pacing (`osd_scrub_wakeup`/`wait_var_event`),
   and re-reading the group bitmap every batch. Half of the total win is
   available with no threads at all.
2. **The curve peaks at 2 and settles ~11% lower.** j2 is the best row on both
   configurations; j3–j16 sit on a flat ~1.80M plateau. More threads past two
   do not help and cost a little. §3 says why.
3. **A mounted client costs ~20%** (1.62M vs 2.03M at j2). The MDS inode cache
   is larger and hotter with a client attached, which lengthens exactly the
   hash walk that §3 shows is the limit. The server-only column is the
   scanner's ceiling; the client-mounted column is the honest number for a
   serving MDT.

## 2. Correctness: identical to the singleton, object for object (both backends)

The harness prints an order-independent FID checksum with every run. Across
**every warm row above** — both configurations, 1 to 16 threads, five shard
sizes, attributes on and off:

```
objects=2000097  attr_ok=2000097  fidsum=a589666c4d4f7123
```

identical, including the singleton baseline rows. The ZFS lab reproduced the
same property with its own checksum — `objects=2000096 attr_ok=2000096
fidsum=39d945cad6c1b98d` in every row of §6a. The sharded private walk returns
exactly the object set the otable iterator returns, with exactly the same
attributes, on both backends. `attr_ok == objects` means `DOIF_ATTR` capture
succeeded for 100% of objects under parallelism, as it did single-threaded in
step 3.

Object counts rise by exactly one per mount cycle (2000097 → 2000100 over three
remounts) — an internal object created at mount, stable again across every run
at a given mount generation. Not a scanner discrepancy, but we did not identify
which object.

## 3. What limits ldiskfs: the kernel's global inode hash lock

`perf record -a -g`, warm, aggregated over the `lfu_par*` threads:

| symbol | j2 | j8 |
|---|---|---|
| `__pv_queued_spin_lock_slowpath` | (spin split across `_raw_spin_lock` 16.8%) | **83.31%** |
| `find_inode_fast` | **36.56%** | 6.48% |
| `ldiskfs_xattr_ibody_get` | 10.73% | 2.25% |
| `__find_get_block` | 5.86% | 1.27% |
| `osd_iit_iget` / `osd_iget2` | 1.65% | 0.26% |

At two threads the profile is dominated by `find_inode_fast` — the icache hash
walk in `iget_locked()`, which runs under the **global `inode_hash_lock`**. At
eight, 83% of all samples are spinning on that lock and `find_inode_fast`
itself collapses to 6%: the threads are no longer doing the walk, they are
queueing for the right to do it.

So the plateau is **not** Lustre's, and not the storage. It is a single
kernel-wide spinlock in `fs/inode.c` that every `iget` on the box contends
for. That has three consequences worth stating plainly:

- **The prediction in the design note was right in mechanism and wrong in
  degree.** It expected sublinear scaling from icache/buffer-cache contention.
  It got that — but the plateau lands at 1.8–2.0M, *twice* the target, so the
  contention costs us headroom we do not currently need.
- **More threads is the wrong next lever.** Going past two enumerators buys
  nothing on this backend. If the ceiling ever needs raising, the move is to
  stop calling `iget` at all — parse inodes straight out of the itable blocks
  the way the userspace device scanner does (which is precisely why *it*
  reaches 4M obj/s at `-j 4` with no kernel inode cache in the path).
  **Done 2026-08-16** (`blockparse-2026-08-16.md`): 17.4M obj/s warm, and the
  new peak is at four threads. The one thing this bullet did not anticipate is
  that `iget` was also supplying a 32-block readahead window cold, so removing
  it is a *regression* until the window is supplied explicitly.
- **It is hardware- and workload-dependent.** `inode_hash_lock` contention
  scales with how many inodes the box is instantiating, including from client
  traffic — which is the mechanism behind the 20% client-mounted penalty.

## 4. Cold on ldiskfs: flat here — but only because this lab's disk was slow

> **Retracted 2026-08-16.** Everything in this section is correct *for a
> 190 MB/s device* and wrong as a general claim. On a 1.4 GB/s NVMe stripe the
> in-kernel cold path scales **3.6× with threads** (202,376 → 731,452 obj/s)
> and never exceeds 51% of the device, while the userspace scanner saturates
> 93% of it with one thread. Cold is **latency-bound** for Option 2, not
> device-bound, and cold is **not** a tie between the options — it is 5.8×
> apart at one thread. See
> [`cold-on-fast-storage-2026-08-16.md`](cold-on-fast-storage-2026-08-16.md).
> The section is kept as measured; read it as a statement about slow storage.

Unmount everything → `drop_caches` → remount the MDT → first pass:

| | rate |
|---|---|
| cold, singleton | 173,619 |
| cold, private j1 | 172,481 |
| cold, private j2 | 173,755 |
| cold, private j8 | 172,526 |

**Flat within 0.7% at every thread count.** Exactly the shape
`option-comparison.md` recorded for the device scanner (flat at every `-j`)
and within 4% of the 08-10 lab's 166–174k cold figures for both options. Cold
is bytes off the device; parallel enumeration is a warm-path lever only, and
the operational rule from 08-10 stands unchanged: **cold obj/s ≈ metadata read
bandwidth ÷ bytes per object.**

This also means the 1M target is a hardware requirement on a first full scan
regardless of this work — but with the CPU ceiling now at 1.8–2.0M rather than
853k, the scanner stays out of the way up to ~2 GB/s of MDT metadata
bandwidth instead of ~870 MB/s.

## 5. Attributes are still free on ldiskfs, now under parallelism

`recattr=0` (bare FID) against `recattr=1` (full tier-0 `lu_attr`), same boot:

| threads | FID only | with attributes | delta |
|---|---|---|---|
| 1 | 1,091,756 | 1,084,651 | −0.7% |
| 4 | 1,515,225 | 1,525,627 | +0.7% |
| 8 | 1,512,932 | 1,529,126 | +1.1% |

Within run-to-run noise, as in step 3 single-threaded. The `DOIF_ATTR` capture
at `osd_iit_iget()` costs nothing when N threads do it at once.

**Shard size barely matters**: 1.51–1.58M at j8 across chunk sizes from 32,768
(one block group, 67 shards) to 1,048,576 (5 shards). Larger shards are
marginally faster — fewer per-shard `init`/`load`/`fini` cycles — but the
1,048,576 row left one of eight threads with no work at all, so the balance
argument beats the overhead argument. **One block group per shard is the right
default**; the dynamic cursor handles skew.

## 6. LFSCK coexistence on ldiskfs — the operational claim, tested

With a **real verifying OI scrub running** (`lctl lfsck_start -t scrub -r`,
`lfu_noverify=0`, status `scanning`):

| iterator | result |
|---|---|
| singleton (`private=0`) | **`err=-114` (`-EALREADY`), 0 objects** |
| private (`DOIF_PARALLEL`, 4 threads) | **2,000,100 objects, same `fidsum`, 1,410,507 obj/s** |

and afterwards the scrub was **undisturbed** — `status: scanning`, `updated: 0`,
`failed: 0`, and it ran to completion (`run_time: 9 seconds`). The private
iterator neither took the `od_otable_it` slot nor called `scrub_stop()`.

That is `design-osd-scanner.md` §8.1's consequence 1 and the K8 operational
risk, closed empirically: **LFU and LFSCK can scan the same target at the same
time**, at 1.41M obj/s while the scrub verifies. The same run demonstrates the
singleton conflict live — the default iterator gets `-EALREADY` under exactly
the conditions where the private one succeeds.

(Consequence 2 — two concurrent LFU scans — is proven by every `nthreads>1`
row: those *are* N concurrent iterator instances on one device.)

## 6a. ZFS — the same patch, a better curve, and a reversed posture

A second lab the same day: identical instance type, Rocky 9.8, **OpenZFS
2.2.10** (the 08-10 lab's version), Lustre v2_17_55 `--with-zfs
--disable-ldiskfs` with the same patch stack plus a bench-only
`osd_zfs_lfu_noverify` knob (`patches/bench-noverify-zfs-v2_17_55.patch`) so
the singleton baseline runs without OI verification too — otherwise the ZFS
A/B compares "no verification" against "verification" and flatters the private
path. MGS+MDT0 on a 24 GiB file vdev, **2,000,333 objects** from the same
`createmany -m` recipe — the exact count the 08-10 lab produced.

| threads | rate | vs singleton |
|---|---|---|
| singleton (`od_otable_it`) | 154,459 | 1.00× |
| private, 1 | 193,713 | 1.25× |
| private, 2 | 315,921 | 2.05× |
| private, 4 | 463,306 | 3.00× |
| private, 8 | 554,043 | 3.59× |
| private, 16 | 561,509 | **3.64×** |

Medians of three, spread ≤3.6%. Same `objects=2000096 attr_ok=2000096
fidsum=39d945cad6c1b98d` in every row including the singleton.

**ZFS scales better than ldiskfs, not worse** — 3.64× against 2.38×, and
where ldiskfs peaked at two threads and fell back, ZFS climbs cleanly to 4
(3.00×, i.e. 75% efficiency) and saturates the 8-vCPU box at 8–16.

The profiles say why. On ldiskfs one global lock takes 83% of j8. On ZFS
**nothing dominates at any thread count**: the top symbol at j8 is
`zrl_add_impl` at 11.3%, followed by `mutex_lock` 10.5%, `_raw_spin_lock`
10.3%, `zrl_remove` 7.0%, `dnode_hold_impl` 3.7%, `dbuf_hold/rele` — a flat
spread of the DMU's per-dnode and per-dbuf hold traffic, the same machinery
`scrub-decomposition-2026-08-07.md` identified as ZFS's per-object cost. That
cost is *distributed*, so it parallelises; ldiskfs's `inode_hash_lock` is
*global*, so it does not. The ZFS plateau at ~560k is the core count, not a
lock — this curve would keep climbing on a bigger box.

**Cold scales on ZFS too**, which it does not on ldiskfs:

| | rate |
|---|---|
| cold, singleton | 97,780 |
| cold, private j1 | 115,625 |
| cold, private j4 | 308,561 |
| cold, private j8 | **424,469** |
| warm reference, same mount, j8 | 500,650 |

Cold j8 is 4.3× cold singleton and only 15% below warm. This is the same
"ZFS is CPU-bound in the DMU, nowhere near the disk" property the 08-10 lab
found for libzpool, now shown to hold in kernel *and* under parallelism. On
ldiskfs, cold is bytes and threads buy nothing; on ZFS, cold is CPU and
threads buy nearly everything.

Attribute capture stays close to free (`recattr=0` vs `1`: 202k vs 194k at
j1, 471k vs 463k at j4 — a 2–4% cost, larger than ldiskfs's ~1% but not
material), and shard size is again insensitive (463k across 16K–128K chunks).

**Coexistence holds identically.** With a real verifying OI scrub running:
singleton → `err=-114`; private j4 → 2,000,096 objects, same `fidsum`,
**392,560 obj/s**; scrub afterwards `status: completed, updated: 0, failed: 0`.

### The posture reversal

`scrub-decomposition-2026-08-07.md` step 2 concluded, in bold: *"on ZFS
today, the userspace device scanner is the faster path; Option 2's case there
rests on liveness and WBCFS, not speed — unless the fan-out-behind-the-
enumerator design lands."* Fan-out never landed that win. Parallel enumeration
does. To settle it without a cross-lab comparison, the userspace ZFS scanner
was built and run **on this same lab, same pool, same namespace** (`make zfs
ZFS_SRC=/usr/src/zfs-2.2.10`, pool exported):

| | obj/s |
|---|---|
| userspace `-j 1` | 81,633 |
| userspace `-j 4` | 172,118 |
| userspace `-j 8` | 218,580 |
| **userspace `-j 16` (best)** | **220,023** |
| userspace `-j 24` | 216,451 |
| **in-kernel private j8, cold** | **424,469 — 1.93×** |
| **in-kernel private j8, warm** | **554,043 — 2.52×** |

The userspace scanner reproduced its known signature exactly: repeating a run
without dropping caches changes nothing (`-j 1`: 24.33s warm vs 24.50s cold),
because libzpool's ARC is process-local and dies with the process. So its
column is the same number cold or warm, while the in-kernel path has both a
warm advantage *and* a cold advantage.

**On ZFS the in-kernel scanner is now the faster path by ~2×, not the slower
one.** Option 2's case on ZFS no longer rests on liveness and WBCFS alone —
though those remain its unique capabilities, and the userspace scanner remains
the only route for an unmounted target, a snapshot, or an unpatched server.

One honest gap in that table: the userspace scanner emits **2,000,009**
objects to the harness's 2,000,096. The 87-object difference is classification
— the userspace core drops internal objects that the raw iterator still
returns — not a missed-object bug; the two agreed exactly on ldiskfs in step 4
when both ran the full classification ladder. The in-kernel harness does no
classification at all, so its count is the iterator's raw output.

## 6b. The head-to-head, every cell from one box

A third lab settled the provenance question: **one Lustre built with both OSDs**
(`--enable-server --enable-ldiskfs --with-zfs`), then, in sequence, the ldiskfs
filesystem → Option 2 on it → Option 1 on that same unmounted device; then the
ZFS pool → Option 2 → Option 1 with the pool exported. Same kernel, e2fsprogs,
OpenZFS, `createmany` recipe and hour throughout. Raw data:
[`bench-data/2026-08-15/same-lab-head-to-head.txt`](../../bench-data/2026-08-15/same-lab-head-to-head.txt).

| | Option 1 · device scanner | Option 2 · OSD scanner, sharded | faster by |
|---|---|---|---|
| **ldiskfs · COLD** *(on this lab's 190 MB/s disk; see the 08-16 retraction)* | 186,402 (flat at every `-j`) | 188,262 (flat at every thread count) | 1.01× — tie *here only*; on NVMe it is 5.8× Option 1 at one thread |
| **ZFS · COLD** | 83,752 (`-j 1`) → 225,480 (`-j 16`) | 97,304 (singleton) → **410,529** (j8) | **1.82× Option 2** |
| ldiskfs · warm, 1 thread | 1,818,270 | 1,249,281 | 1.46× Option 1 |
| ldiskfs · warm, parallel | 4,545,675 (`-j 4`) | 2,066,219 (j2) | 2.20× Option 1 |
| ZFS · warm, 1 thread | 84,282 | 186,038 | **2.21× Option 2** |
| ZFS · warm, parallel | 230,151 (`-j 16`) | **531,940** (j16) | **2.31× Option 2** |

Three things this settles:

1. **ldiskfs cold is a genuine tie** — 186.4k against 188.3k, both flat at every
   thread count. Neither scanner is near its own CPU limit there; the device is.
2. **ldiskfs warm: Option 1 still leads, by 2.2× rather than the ~5× the old
   record implied.** Its enumerator parallelises with no kernel inode cache in
   the path — precisely the ceiling §3 shows Option 2 hitting.
3. **ZFS: Option 2 leads every row**, and neither column benefits from a warm
   cache (libzpool's ARC is process-local; the in-kernel path is CPU-bound
   anyway). On that backend the whole contest is CPU, and sharding wins it.

**It also reproduced both namespaces exactly** — `fidsum a589666c4d4f7123` on
ldiskfs and `39d945cad6c1b98d` on ZFS, identical to the single-backend labs —
and every rate agreed with those labs to within ~8%, *including the in-kernel
warm figures*. That is the first time this project has reproduced an in-kernel
warm rate across labs; the 832k-vs-390k gap recorded in August did not recur.

## 7. What this changes

| Record | Was | Now |
|---|---|---|
| `design-osd-scanner.md` §8.1 | singleton is a hard ceiling; fan-out mandatory *because of it* | binds the default iterator only; fan-out still wanted for one-scan-N-consumers, not for parallelism |
| K4 (throughput) | 832k single-thread, "within 20% of 1M" | **2.03M at j2, 1.25M at j1** — target cleared with margin. *(08-16: 17.4M warm, 1.42M cold at 99% of an NVMe stripe)* |
| K8 (LFSCK coexistence) | biggest operational risk; hours of blocked scanning | **resolved** — measured concurrent, scrub unharmed |
| step-2 fan-out | the lever for per-object work | still valid for tier-2 work; no longer the parallelism story |
| **ZFS posture** (step 2) | "the userspace device scanner is the faster path; Option 2's case there rests on liveness and WBCFS, not speed" | **reversed** — in-kernel sharded is **2.31× warm / 1.82× cold** the userspace scanner's best, on a box running both (§6b) |
| ZFS scaling | fan-out breaks even; the producer's cost is inherent | the producer's cost is inherent *per object* but **distributed across locks**, so it shards: **3.64×**, better than ldiskfs |
| LU-20591 reply | "we think it can be parallelized, not measured yet" | measured; the promised scaling curve exists |

Still open, and now the interesting ones:

- ~~ZFS is untested.~~ **Done (§6a)** — and it scales better than ldiskfs.
- **Foreground impact under client load** is unmeasured for the parallel path
  on either backend. Two enumerator threads at 2M obj/s contend for
  `inode_hash_lock` with the MDS's own service threads; the 20% client-mounted
  penalty on ldiskfs is a hint that the interference is real and bidirectional.
  On ZFS, where the useful thread count is 8+ rather than 2, the question is
  sharper still. `throughput-test-plan.md`'s foreground methodology applies
  unchanged, and **this is now the most important open item.**
  *(08-16: block parsing changes the shape of this question on ldiskfs rather
  than removing it. The scan no longer contends for `inode_hash_lock` at all —
  it contends for the buffer cache and the device instead, and it does so ~10×
  faster. Still the most important open item.)*
- **The osd-zfs `load()` off-by-one** from the design note (§5) is *consistent
  with* the ZFS lab but not isolated by it: the private path (patched to start
  at `hash`) returns the identical FID set the singleton does, which is what
  the patch intends, but no test exercised the *default* path's
  checkpoint/resume to show the skip directly. Still worth a targeted test
  before raising it upstream.
- **Upstream shape.** `DOIF_PARALLEL = 0x0020` collides with nothing today but
  `DOIF_ATTR = 0x0010` collides with Jinshan's `DOIF_NOSCRUB`; on rebase
  `DOIF_PARALLEL` should imply `NOSCRUB`. A feature bit would beat discovering
  support via `-EALREADY`.

## 8. Method notes, for the next person

- **`llmount.sh` does not run on Rocky 9.8.** `test-framework.sh`'s
  `stack_trap` builds a trap string via `trap -p` and `eval`s it; on this
  bash it dies with ``unexpected EOF while looking for matching `'`` at line
  7427. The lab was built by hand (`mkfs.lustre` + `mount -t lustre` for
  MGS+MDT, OST, client) — five commands, and it gives direct control of the
  MDT geometry.
- **`downloads.lustre.software/repository/*` now 404s**, including the GPG
  key path in `notes/reference/build_install.md` §3.1. Use
  `https://downloads.whamcloud.com/public/e2fsprogs/latest/el9/`.
- **`kernel-debuginfo-common-x86_64-$(uname -r)` remains mandatory** and
  silent when missing. `ENABLE_LDISKFS='yes'` in `config.log` was checked
  before `make`, per the standing rule.
- **Do not use bare `wait` in a script whose stdout is a `>(tee …)` process
  substitution** — bash counts the tee as a job, so `wait` blocks forever
  after the real children exit. Cost an otherwise-finished populate step.
- The full build (deps → clone → patch → configure → `make -j8` → install)
  took **~8 minutes** on a c3-standard-8; the whole lab, from
  `instances create` to first measurement, about 25.
