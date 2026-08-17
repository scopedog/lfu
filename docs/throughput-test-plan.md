# Test Plan — Scan throughput, Option 1 vs Option 2

> **Executed 2026-08-06 — results in `throughput-results-2026-08-06.md`.** Scrub 105 k
> obj/s vs scanner 705 k inodes/s on identical hardware (6.7×); foreground
> impact equal (~−5%); torn-read skips 0.05% worst case (Andreas's <1%
> prediction confirmed). Verdict per §3 gate: Option 2 prototype not justified
> on current evidence.
>
> **Overtaken 2026-08-15/16 — the gate measured the wrong thing.** The plan's
> premise (§1) was that OI Scrub's rate "is an upper bound for Option 2", since
> Option 2 reuses `osd_iit_next()` → `osd_iit_iget()`. That held only while
> Option 2 was obliged to reuse *both* calls. `DOIF_PARALLEL` removed the
> singleton and block parsing removed `osd_iit_iget()` itself, and the same path
> now measures **17.4M obj/s warm** and **1,420,664 cold at 99% of an NVMe
> stripe** — 1.01× the device scanner, where this plan recorded 6.7× against.
> See [`parallel-osd-measured-2026-08-15.md`](parallel-osd-measured-2026-08-15.md)
> and [`blockparse-2026-08-16.md`](blockparse-2026-08-16.md).
>
> The methodology is still good and §4's foreground procedure is still the one to
> use — that measurement remains the open item. What to carry forward: an
> existing consumer's rate bounds *that consumer*, not the path, and a gate built
> on one is a gate on the incumbent implementation.

Goal: answer the two throughput unknowns **before** deciding whether the
Option 2 kernel prototype is worth building.

| Unknown | Where tracked | How answered here |
|---|---|---|
| Does the OSD iterator path reach ~1M objects/sec/MDT? | *Scan throughput* (`design-osd-scanner.md` §10) | Measure **OI Scrub** on a realistically-populated MDT — it walks `osd_iit_next()` → `osd_iit_iget()`, the exact path Option 2 would reuse, so its rate is an upper bound for Option 2. Zero development effort |
| What is Option 1's real (cold-cache) throughput? | `design-ldiskfs-scanner.md` §17 "Not measured" | Run the existing prototype on the same MDT, cold cache |

Both require the same prerequisite: an MDT large enough that the inode table
does not fit in page cache. The current lab MDT (~1 800 inodes in use, 100 000
total) cannot answer either question — every number it produces is a cache-hit
figure.

The comparison metric is **not** raw objects/sec alone. Option 2's cost lands
on the MDS; Option 1's mostly does not. The deciding number is *scan rate at a
bounded impact on foreground metadata performance*, so every scan is measured
twice: idle, and against a concurrent client metadata load whose degradation is
recorded.

---

## 1. Prerequisite — a realistically-populated MDT

### 1.1 Sizing

Target: **≥ 10M allocated inodes**, so the inode table alone is ≥ 10 GiB
(1024 B MDT inodes) and cannot be cache-resident on a reasonably-sized VM.

- New virtual disk for the MDS VM: **64 GiB** (`/dev/vdc` or similar).
  `mkfs.lustre --mdt` defaults give roughly one inode per 2.5 KiB, so 64 GiB
  yields ~25M inode slots; populate 10–15M of them.
- MDS VM RAM: keep at **≤ 8 GiB** during measurement runs, so a 10 GiB+ inode
  table cannot be fully resident. If the VM has more, either shrink it for the
  runs or rely on §3's explicit cache-drop discipline and say so in the report.

### 1.2 Honest device I/O from a VM

The virtio disk must not be write-back cached by the host, or "device
bandwidth" is really host page cache:

- libvirt disk XML: `<driver name='qemu' type='raw' cache='none' io='native'/>`
- Verify from the guest that reads actually hit the host device
  (`iostat -x 1` on the host while scanning).

Record host storage type (NVMe/SSD/HDD) in the results — the absolute numbers
are only meaningful alongside it.

### 1.3 Format and mount

```bash
# MDS node — new MDT for the benchmark filesystem (or reformat testfs with
# --reformat if the existing lab namespace is disposable)
mkfs.lustre --mdt --fsname=benchfs --index=0 --mgs /dev/vdc
mount -t lustre /dev/vdc /mnt/benchfs-mdt0
```

### 1.4 Population

Use `createmany` from lustre-tests (installed with the test RPM on the client):

```bash
# Client — 1000 dirs x 12k files = 12M inodes, mknod-only (-m):
# no OST objects, so population speed is bounded by the MDS alone.
mkdir /mnt/benchfs/pop
for d in $(seq 0 999); do
    mkdir /mnt/benchfs/pop/d$d
    createmany -m /mnt/benchfs/pop/d$d/f 12000
done
```

Notes:

- `-m` (mknod) files have no layout; if tier-1 xattr realism matters for the
  Option 1 run, populate a slice (say 1M files) with `createmany -o` so those
  carry real LOV EAs. Record the mix.
- At a VM-typical 2–5k creates/sec this is **1–2 hours**. It is a one-time
  cost; snapshot the populated disk image afterwards so every run starts from
  identical state.
- Record final `df -i` on the MDT and `dumpe2fs -h` output.

---

## 2. Foreground-load harness

The same client load runs during the "under load" variant of every scan:

```bash
# Client — sustained mixed metadata load in a separate tree
mdtest -n 5000 -i 50 -d /mnt/benchfs/load -u
# or, if mdtest is unavailable: a loop of createmany -m / rm -rf
```

**Baseline first:** run the load with *no scan* three times; record ops/sec.
This is the number degradation is measured against.

---

## 3. Procedure A — OI Scrub rate (answers the throughput question)

Every run starts cold:

```bash
# MDS
sync; echo 3 > /proc/sys/vm/drop_caches
```

### A1 — idle filesystem

```bash
# Start a full, unthrottled scrub (-r reset, -s 0 = no speed limit)
lctl lfsck_start -M benchfs-MDT0000 -t scrub -r -s 0

# Sample once per 10s until status leaves "scanning"
watch -n 10 'lctl get_param osd-ldiskfs.benchfs-MDT0000.oi_scrub'
```

Record from the final output: `checked`, `run_time`, `average_speed`; and the
`real_time_speed` samples over the run (it reports both — `scrub_dump()`,
`obdclass/scrub.c:562-605`). Also capture `iostat -x 10` on the MDS for the
duration, and MDS CPU (`pidstat -t 10` on the scrub thread).

### A2 — under client load

Same as A1 with the §2 harness running. Record scrub `average_speed` **and**
mdtest ops/sec vs baseline.

### Interpreting the result

The scrub rate is a *bound*, not a prediction, and it is approximate in both
directions:

- Scrub does OI-table lookup/verify work per object that LFU would not do
  → understates the LFU-attainable rate.
- Scrub captures no attributes and takes no per-object references beyond the
  LMA read; LFU's attribute capture (§3.1 of the OSD design) adds work
  → overstates it.

Both effects are per-object CPU, not I/O, so on a cold-cache run where the
inode table dominates, the scrub number should be close. State both caveats in
the report.

### Decision gate

| A1 result | Reading |
|---|---|
| ≥ ~1M objects/sec | Throughput risk retired at this scale; Option 2 prototype justified on performance grounds |
| ~300k–1M | Plausible but not proven; Option 2 viable if A2 degradation is acceptable — prototype justified, the throughput question stays open |
| ≤ ~300k | Throughput essentially confirmed as a blocker at this storage class; Option 2 needs a different iteration strategy before a prototype is worth writing |

(Thresholds are for the lab's storage class; scale expectations to the §1.2
recorded hardware.)

---

## 4. Procedure B — Option 1 prototype on the same MDT

Same cold-cache discipline (`drop_caches` on the MDS before each run — the
prototype reads through the buffered block device, so the page cache it could
hit is the same one).

### B1 — idle filesystem

```bash
# MDS
sync; echo 3 > /proc/sys/vm/drop_caches
time ./build/lfind-ldiskfs -q /dev/vdc
```

Record: wall time, inodes/sec (allocated-inode count ÷ wall time), the
`skipped: csum=N validate=N` line, `iostat -x` during the run, and scanner CPU.

### B2 — under client load

Same with the §2 harness running. Record:

- scanner rate (expected to drop — it now competes for the device with journal
  commits);
- mdtest ops/sec vs baseline (expected impact: device contention + one core);
- the `validate=` skip count — this re-runs the §8.2 torn-read measurement at
  realistic scale, replacing the 880/1740 small-sample figure. Prediction to
  confirm (Andreas, 2026-08-06): the affected set is bounded by the journal
  commit window (~5–10 s of creates), so at 12M inodes the skip fraction
  should be well under 1% even under sustained load.

### B3 — repeat runs

Three runs per variant minimum; report median and spread. Single-run numbers
from VMs are noise.

---

## 5. What to record — results table skeleton

| Run | Cold? | Client load? | Rate (obj/s) | mdtest vs baseline | MDS CPU | Device util % | Skips |
|---|---|---|---|---|---|---|---|
| A1 scrub ×3 | yes | no | | n/a | | | n/a |
| A2 scrub ×3 | yes | yes | | | | | n/a |
| B1 option1 ×3 | yes | no | | n/a | | | validate= |
| B2 option1 ×3 | yes | yes | | | | | validate= |

Plus, once: population size (`df -i`), disk/host storage class, VM RAM,
`dumpe2fs -h`, Lustre version, e2fsprogs version.

---

## 6. Explicitly out of scope

- **Building the Option 2 prototype.** That decision is this plan's *output*
  (§3 decision gate), not its input.
- **The singleton constraint (*LFSCK coexistence*).** "No LFU scan while LFSCK runs" is a
  design fact no benchmark changes; it stays a conversation with operations.
- **ZFS.** Nothing here transfers to osd-zfs; its iterator has no inode
  bitmap and needs its own measurement if Option 2 proceeds.

## 7. Effort estimate

| Step | Estimate |
|---|---|
| Disk add + format + populate + snapshot (§1) | half a day, mostly unattended |
| Baseline + Procedure A | ~half a day |
| Procedure B | ~half a day |
| Write-up | hours |

Against this: an Option 2 kernel prototype is realistically **weeks** (patched
build → install → reboot cycle; failures are MDS panics; no userspace test
harness). This plan is the cheap experiment that decides whether to spend that.
