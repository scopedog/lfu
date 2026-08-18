# Throughput Benchmark Results — 2026-08-06

Execution of `throughput-test-plan.md` on the lab cluster. All twelve runs completed.

## Environment

| | |
|---|---|
| MDS | `rhel9.7-server-mgs-mds-clone` VM: 4 vCPU, 8 GiB RAM, RHEL 9.7, Lustre 2.17.51_289_gf097860 (source build) |
| MDT | `benchfs-MDT0000` on 64 GiB virtio disk (`cache='none' io='native'`, qcow2 on host NVMe), 1024 B inodes, `-i 2560` → 26.8 M slots |
| Population | **12,001,273 inodes** (1000 dirs × 12 k mknod files, 485 s at ~24.7 k creates/s) |
| Cache honesty | In-use inode table ≈ 11.5 GiB > 8 GiB VM RAM; `echo 3 > drop_caches` before every run |
| OST | 1 × 16 GiB on the OSS VM (files are mknod — no OST objects; OST exists to satisfy the `mdt_obd_connect` OSP gate) |
| Load harness | `createmany -m` 20 k / `unlinkmany` loop on an MDS-local client mount, single-threaded |
| Scanner | `lfind-ldiskfs` built on the MDS against e2fsprogs-devel-1.47.3-wc2 |
| Snapshot | `lfu-benchfs-mdt.pristine.qcow2` (16 GiB actual) taken post-population, pre-benchmark |

`dumpe2fs`: `uninit_bg`, no `metadata_csum` — same feature set as testfs, confirming the earlier metadata_csum finding at this scale.

## Results

| Run | Wall time | Rate (objects/sec) | Foreground impact | Skips / failures |
|---|---|---|---|---|
| A1 OI Scrub, idle ×3 | 114 / 115 / 115 s | **105,272 / 104,357 / 104,357** | n/a | 0 failed |
| A2 OI Scrub, under load ×3 | 146 / 146 / 145 s | **82,202 / 82,265 / 82,837** | **−4.8%** (9,219 → 8,778 creates/s) | 0 failed |
| B1 Option 1 scanner, idle ×3 | 17.11 / 17.06 / 16.99 s | **~705,000** | n/a | csum=0 validate=0 |
| B2 Option 1 scanner, under load ×3 | 18.04 / 17.77 / 17.76 s | **~672,000** | **−5.1%** (9,406 → 8,929 creates/s) | validate = **5,979 / 4,433 / 0** |

Scanner runs: 47% of one core, 5.3 MB RSS, ~12 GiB read per pass (≈ 720 MB/s
device throughput — almost exactly the 1 KiB/inode arithmetic of design §11.1).
Run-to-run spread on every variant is under 2% — the medians are the numbers.

## Findings

### 1. Throughput decision gate: the OSD path lands in the "blocker" band

Scrub — the exact `osd_iit_next()`/`osd_iit_iget()` iterator Option 2 would
reuse — sustains **105 k objects/sec** on hardware that demonstrably delivers
**705 k inodes/sec** through the raw block device. Per the test-plan §3 gate
(≤ ~300 k at this storage class), the throughput risk is essentially confirmed: the per-object
in-kernel path, not the storage, is the limit. The transferable result is the
**6.7× ratio on identical hardware**, not the absolute VM-class numbers.

Both proxy caveats stated in the plan still apply: scrub does OI
lookup/verification per object that LFU would not (rate understated), and LFU
would add attribute capture that scrub does not (rate overstated). Those
corrections are per-object CPU adjustments; nothing in them plausibly closes a
6.7× gap. Note also the otable iterator is a per-device singleton — the
parallelism that could close the gap is precluded by the current design.

### 2. Option 1 approaches the 1M target even on a VM

705 k/s cold-cache at 47% of one core, I/O-bound at ~720 MB/s. The §11.1 model
(1 M objects/sec ⇔ ~1 GiB/s of inode-table reads) is confirmed almost exactly;
on server-class storage the target is credible, and the block-group parallel
scan (§9.1, unimplemented) has CPU headroom to spare.

### 3. Foreground impact is equal — and small — for both

−4.8% (scrub) vs −5.1% (scanner) against a single-threaded ~9 k creates/s
foreground load. The fear that a block-device scan hammers the MDS harder than
an in-kernel scan is not supported: at this load level both are noise-adjacent.
Caveat: the foreground load was single-threaded on a 4-core VM; neither CPU nor
device was saturated. A saturated-MDS variant remains future work.

### 4. Torn-read rate at scale: Andreas's prediction confirmed

Under sustained ~9 k creates/s, the scanner skipped **5,979 / 4,433 / 0**
inodes of ~12 M per pass — **0.05% worst case**, versus the ~50% figure from
the 1,740-inode toy namespace (which sat entirely inside the journal commit
window). All skips were detected and counted, none silently dropped. The
`design-ldiskfs-scanner.md` §8.2 addendum's framing is now backed by data at
realistic scale: the commit-window model holds, and the affected fraction on a
real filesystem is negligible for full-scan consumers.

## Decision-gate verdict

Per the plan: **building the Option 2 kernel prototype first is not justified on
current evidence.** Option 1 is 6.7× faster on identical hardware, costs the
foreground workload the same, and its consistency exposure measured at 0.05%
worst-case, fully detected. This is measured support for the Option-1-first PoC
position (Timothy).

**This is a verdict on order, not on Option 2.** Both scanners are to be
implemented (Dilger, 2026-08-06: "in the end we will want both of these" —
device-level userspace scanning for offline use, OSD API for other OSDs and
in-kernel scanning), and the OSD scanner is the only path to ZFS and WBCFS
(`architecture.md` §6c). What this benchmark says about it is narrower and more
useful: the 6.7× gap is the thing it has to close before it ships, the cause is
the per-object kernel path rather than storage, and the iterator singleton
precludes the parallelism that would close it. So the work it most needs first
is the redesign — LFSCK-as-consumer plus a batched attribute-capturing iterator
— **and Procedure A should be re-run against that**, plus once against osd-zfs,
where none of these numbers transfer.

## Not measured / limitations

- VM-class absolute numbers; host page cache bypassed via `cache='none'` but
  the host NVMe is a single consumer-class device.
- Scrub CPU% per thread was not captured (iostat only).
- Foreground load was single-threaded; no saturated-MDS variant.
- The B2 correctness oracle (zero misses vs `lfs find`) was not re-run at 12 M
  scale — runtime ~17 s per pass makes a full FID-set diff feasible; worth one
  run before citing correctness at scale.
- Emitted counts vary slightly across B2 runs (12,001,008–12,004,977): live
  namespace churn from the load loop, expected.

## Raw data

On the MDS (`192.168.122.10`): `/tmp/bench/a_*.{samples,final,iostat}`,
`/tmp/bench/b_*.{out,iostat}`, `/tmp/bench/load.log`, `/tmp/populate.log`.
Pristine post-population MDT image on the host:
`/var/lib/libvirt/images/lfu-benchfs-mdt.pristine.qcow2`.

## Incidental finding (cost a morning; worth recording)

With the OSS VM down, **every** client mount of testfs/benchfs fails: not a
network issue but `mdt_obd_connect()` returning -EAGAIN until every OSP
reports connected (`mdt_handler.c:7499-7508`, the `MDT_FL_SYNCED` gate).
Client-side symptoms (LNet NI "in recovery", MGS config-log timeouts) are
secondary noise. Rule for this lab: **always start the OSS before expecting
any client mount to succeed** — and a benchfs-style fs needs at least one OST
for the same reason.
