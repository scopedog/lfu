# ldiskfs Scanner on a Real Packaged-Lustre MDT — Common Core + `-j`

**Date:** 2026-08-07
**Companion to:** `design-common-core.md` (the refactor this validates) and
`zfs-mdt-verification-2026-08-07.md` (the ZFS half of the comparison).

## The lab

GCP `lustre-ldiskfs-lab`, c3-standard-8 (8 vCPU), Rocky 9.8 userland — same
instance type as the ZFS run.  Lustre **2.17.0-291 from packages** (first
packaged-server deployment in this project; both prior labs were source
builds), single node: MGS+MDT0 on `/dev/loop0` (20 GiB image), OST0 on loop,
local client.  Populated with the same shape as the ZFS run: the 1,026-FID
oracle tree plus 300,000 `createmany` files (16,955 creates/s).  Scans ran
against the unmounted MDT device.

## Correctness on the real MDT

```
inodes seen 301,299 · in use 301,288 · emitted 301,033 · csum=0 validate=0
```

- **Oracle: 0 missed** — every `lfs path2fid` FID found by the scanner.
- Extras = exactly the 300k `createmany` files + root/`.lustre` internals.
- **`-j 4 / 8 / 24` output byte-identical to `-j 1`** — the parallel
  block-group scan (per-worker `ext2_filsys`, private inode bitmap,
  `ext2fs_inode_scan_goto_blockgroup()`) is a pure throughput change.
- 1 `no-lma` object — consistent with the ldiskfs picture, and three orders
  of magnitude away from the 230 that are *normal* on osd-zfs.

An accidental but useful observation: with `uninit_bg`, groups whose inode
table was never initialised are skipped wholesale, so `seen` ≈ allocated
(301k of an 8.4M-inode table).  Last week's 12M-inode benchmark had every
group populated and could not show this.  Consequence: device-scan cost
scales with the *populated* portion of a young MDT, not its formatted size —
and, conveniently, it makes today's ldiskfs and ZFS runs count the same
~301k objects.

## Throughput — and the shape of the bottleneck

Cold = after `drop_caches`; warm = best of 3.

| `-j` | cold | warm |
|---|---|---|
| 1 | 1.64 s | 0.17 s |
| 2 | 1.64 s | 0.11 s |
| 4 | 1.64 s | **0.07 s** |
| 8–24 | 1.64 s | 0.08 s |

Two clean signals:

1. **Cold is flat at every thread count** — 1.64 s ≈ the loop image's
   metadata read at pd-balanced streaming rate.  Cold ldiskfs scanning is
   **I/O-bound**; `-j` buys nothing there and doesn't need to.
2. **Warm scales to ~4M obj/s at `-j 4`** then hits the measurement floor
   (70–80 ms on 301k objects is too small to resolve further).  The CPU
   path — inode parse + inline LMA parse — is cheap and parallelises.

## The equal-parallelism comparison the record owed

Same instance type, same object count (301k), both scanning an unmounted
real MDT of their backend:

| | `-j 1` | best `-j` | bound by |
|---|---|---|---|
| **ldiskfs** (warm) | ~1.77M obj/s | ~4M obj/s (`-j 4`) | measurement floor |
| **ldiskfs** (cold) | ~184k obj/s | ~184k obj/s (flat) | device streaming rate |
| **ZFS** | 87.6k obj/s | 274k obj/s (`-j 24`) | libzpool lock contention |

The honest one-line summary: **the ldiskfs read path is I/O-bound and the
ZFS read path is CPU-bound**, and that — not any single rate — is the
transferable result.  ldiskfs cold-vs-warm differs 10×; ZFS cold-vs-warm
differed 2%.  On server-class storage the ldiskfs scanner will track the
device; the ZFS scanner will track `dnode_hold_impl` unless its shared-state
contention is addressed.  Rates here are cloud-VM class with page-cache-warm
loop images; ratios and boundedness transfer, absolute numbers do not.

## Deployment notes (packaged server on GCE)

- `kmod-lustre-osd-ldiskfs-2.17.0-291.el9` has **RHEL 9.7 kABI** — on a 9.8
  system, install `kernel-5.14.0-611.20.1.el9_7` from the Rocky vault and
  boot it.
- `dnf install lustre` alone resolves toward broken `lustre-zfs-dkms`;
  install `kmod-lustre*` + `lustre-osd-ldiskfs-mount` first, `lustre` second.
- Stock Rocky e2fsprogs (1.46.5) lacks `ext2fs_xattrs_read_inode()`; the
  Lustre-patched 1.47.3-wc2 provides it (needed to *build* the scanner).
- `createmany` lives in `lustre-tests`.

## Operational self-inflicted wounds, recorded so they stay unique

- `umount -l` on a Lustre client whose MDT/OST are already gone leaves an
  unflushable superblock: the next `sync` hangs in D-state **forever**, and
  later `drop_caches` writers pile up behind it.  Never lazy-unmount a
  Lustre client during teardown; unmount the client first (shutdown order
  exists for a reason), and if the cwd is inside the mount, `cd` out.
- `pkill -f <script>` inside an `ssh` command matches the SSH session's own
  command line and kills the session — including any commands (like
  `reboot`) queued after it.  Use a `[.]` bracket in the pattern, or
  separate sessions.
