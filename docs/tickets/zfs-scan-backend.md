# ZFS backend behind `llapi_scan_device()` — ticket to file

**Not filed yet.** Technical task, **parent LU-20462**, related to **LU-20606**
(the ldiskfs backend it mirrors) and **LU-20611** (`lfind(8)`, its consumer).
Assignee Hiroshi Nishida, Affects Version **2.18.0**. The LU project defines no
components, so that field stays empty as it does on every other ticket there.

Step 3b of [`architecture.md`](../architecture.md) §12. Design of record:
[`design-zfs-scanner.md`](../design-zfs-scanner.md). Measurements:
[`zfs-mdt-verification-2026-08-07.md`](../measurements/zfs-mdt-verification-2026-08-07.md).

---

## Summary

llapi: ZFS backend for `llapi_scan_device()`

## Description

The second backend behind the entry point LU-20606 introduced: `scan_zfs.so`,
reading a Lustre-on-ZFS MDT or OST dataset through libzpool, emitting the same
`struct llapi_scan_rec` to the same sink, with no mounted Lustre server.

**Why now rather than later.** The plugin split's whole claim is that the
backend ABI generalises past the backend it was written for. One backend does
not test that claim. This is the cheapest test of it, and running the test while
LU-20606 is still in review is what makes any ABI change free — after the first
plugin ships, the same change is a compatibility event.

**Most of it exists.** The prototype is 605 lines against the ldiskfs scanner's
693, passes 16 of 16, and has been verified against an MDT built by osd-zfs
itself rather than a synthetic rig: 87,600 obj/s single-threaded and 274,000 at
`-j 24` on 8 vCPUs, output identical at every thread count. Its unit of work is
already **object-ID ranges** — `dmu_object_next()` takes a start position — which
is the direct analogue of the block-group chunking the backend ABI is built
around. That is the part that had to fit, and it does.

**Packaging is a solved problem in tree.** `mount_osd_zfs.so` is already built
under `if ZFS_ENABLED` / `if PLUGINS` and already links `-lzfs -lnvpair
-lzpool` through `ZFS_LIBZFS_LIBS`. `scan_zfs.so` is the same shape beside it,
exactly as `scan_ldiskfs.so` is the same shape as `mount_osd_ldiskfs.so`. The
objection one would expect — that libzpool is an unstable internal OpenZFS API —
is pre-answered by the tree already depending on it.

### In scope

- MDT and OST datasets of a Lustre-on-ZFS filesystem, read-only, never writing
  to the pool.
- The same record, the same demand mask and the same I/O cost tiers as the
  ldiskfs backend.
- Snapshot as the default operating mode; a snapshot is atomic and near-free,
  so the torn-read problem the ldiskfs backend lives with does not arise.
- `--target` and `--local` resolution for ZFS targets in `lfind(8)`.

### Out of scope

- Repair of any kind. Not `zdb -c`, not scrub, not LFSCK.
- The in-kernel OSD path, which is 2.19 work and LU-20591's ground.
- `traverse_dataset()` prefetch (route 2), still unimplemented and still
  unmeasured on disk-backed storage with a cold ARC.

### The one thing to settle first

**Every measured run so far did snapshot, then export, then scan.** `lfind
--local` on a serving MDS is the *imported*-pool case, which is the one that has
not been proved. Either a snapshot of an imported pool reads cleanly through
libzpool, or ZFS targets carry an "export the pool first" caveat — and that
choice changes the interface, the man page and what `--local` may claim. It
wants a lab before the port, not during it.

### Acceptance

- `llapi_scan_device_test.c`, the contract tests written for ldiskfs, pass
  **unmodified** against a ZFS target. This is the ABI generalisation claim
  stated as a test rather than as a design argument.
- The conf-sanity 165 scan finds every visible FID on a ZFS MDT, as it does on
  ldiskfs.
- The object set is identical at 1, 2, 4, 8 and 16 threads.
- `liblustreapi` still links neither libext2fs nor libzpool; both stay behind
  their plugins.

---

## Paste into Jira

Written for the rich-text editor, per the recipe that came through byte-exact on
LU-20611: no double hyphens outside the code fence, no asterisks, no braces, and
triple backticks for anything that must survive literally. Kept short on purpose
— the argument for it is in this file, not on the ticket.

~~~
scan_zfs.so, a second backend behind the llapi_scan_device() entry point
from LU-20606. It reads a Lustre on ZFS MDT or OST dataset through
libzpool and emits the same llapi_scan_rec to the same sink, with no
mounted Lustre server.

h5. Why now
A second backend is the only real test that the backend ABI generalises.
While LU-20606 is in review an ABI change is free; once the first plugin
ships it is a compatibility event.

h5. What already exists
A working prototype, 605 lines to the ldiskfs scanner's 693, verified
against an MDT built by osd-zfs itself: 87,600 objects per second single
threaded, 274,000 at 24 threads, identical output at every thread count.
Its unit of work is object ID ranges, which is what the backend ABI
already chunks by.

h5. Packaging
The same shape as mount_osd_zfs.so, which is built under ZFS_ENABLED and
PLUGINS and already links
```
-lzfs -lnvpair -lzpool
```

h5. Scope
MDT and OST datasets, read only, snapshot by default. The same record,
demand mask and cost tiers as the ldiskfs backend. Target and local
resolution for ZFS targets in lfind. Not repair, and not the in kernel
OSD path, which is 2.19 work.

h5. To settle first
Every run measured so far snapshotted, exported, then scanned. Running
lfind on a serving MDS is the imported pool case, and that one is not
proved. Either a snapshot of an imported pool reads cleanly through
libzpool, or ZFS targets need the pool exported first, and that changes
the interface rather than only the code.

h5. Acceptance
The contract tests written for ldiskfs pass unmodified against a ZFS
target. The conf-sanity 165 scan finds every visible FID on a ZFS MDT.
The object set is identical at 1, 2, 4, 8 and 16 threads. And
liblustreapi links neither libext2fs nor libzpool.
~~~
