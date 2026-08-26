# LFU Phase 1 — progress against the HLD

*LU-20462 · 2026-08-26 · Phase 1 = userspace, Lustre 2.18*

Every module the HLD names as initial and either client- or device-side is
written and in review. What is left in Phase 1 is the stream format, the modules
that depend on it, and the indexes — and the format decision is not ours to make.

| | |
|---|---|
| Changes in review | **19** |
| LU tickets, all In Progress | **8** |
| Upstream bugs found and fixed on the way | **4** |
| **Landed** | **0 — none has been merged yet** |

The last number is the one that matters. Everything below is written, built,
lab-verified and posted for review; nothing has been merged. Fifteen of the
nineteen changes are LFU feature work; four are pre-existing upstream defects
found while building on the code and fixed separately rather than folded in.

**The four bugs are worth counting as output.** LU-20624 (a stale descriptor in
`cb_get_dirstripe`), LU-20643 (`lfs find` answering `-btime` from a reused
buffer), LU-20647 (a plainly registered changelog user could not be looked up at
all) and LU-20648 (`--mask` silently dropped for a user who has none). None was
introduced by this work. Three were found by reading the code the scanner was
being built on; the fourth by the first lab run of the changelog module.

## The HLD modules, one by one

### Base requirements

| Module | Status | Where |
|---|---|---|
| Modular architecture — Input Scanner / Filter Rule / Output Format | in review | the three types are real and separable: four input scanners, `find_decide()` as the filter, the output half of `lfs find` |
| Efficient binary data exchange — the Object Stream format | **not ours** | FlatBuffers vs Cap'n Proto, taken off our plate 2026-08-19; evaluation not started |
| Scanning and filtering performance — 1M obj/s/MDT | **met** | 1,435,080 obj/s measured; see the condition below |
| No dependence on an external database | held | nothing in the design or the code introduces one |

### Server-side changes

| Module | Status | Where |
|---|---|---|
| ldiskfs Device Input Scanner | in review | 68156 — LU-20606 |
| Changelog Input Scanner | in review | 68415 — LU-20649 |
| Changelog Output Filter | not started | designed and partly *refused*: the MDS has only SOM, so a size filter there would drop big files |
| Index Input Scanner — OST object index, oldest atime, largest file | not started | — |
| Binary Object Stream format | **not ours** | blocks the RPC modules and every cross-node use |
| OSD API Input Scanner | **Phase 2** | prototyped and measured, not submitted |
| Kernel API for Object Stream — the `circ_buf` ring | **Phase 2** | designed against `ofd_access_log.c` as precedent |
| Server Bulk RPC Filter Rule | **Phase 2** | needs the format first |

### Client-side changes

| Module | Status | Where |
|---|---|---|
| Lustre Namespace Input Scanner | in review | 68094 — LU-20603 |
| `lfs find` Filter Rule and Output Format | in review | 68095, 68157, 68158, 68159 — LU-20605, LU-20611 |
| FID → pathname Output Format | in review | 68288 — LU-20637 |
| POSIX Input Scanner | not started | the namespace walk now survives crossing onto non-Lustre, which is not the same thing |
| Client Bulk RPC Filter Rule | **Phase 2** | needs the format first |

### Future improvements, per the HLD

| Module | Status |
|---|---|
| Structured output formats — JSON, BSON, Parquet | not started |
| Internal indexes, maintained by the MDS | not started |
| Persistent aggregates | not started — the HLD itself suggests integrating with GUFI instead |

## The performance target, and the condition on it

The HLD asks for **1M objects/s per MDT, assuming at least 1 GiB/s read on the
MDT device, exclusive of pathname generation**. Measured 2026-08-16 against
exactly that, on a 1,406 MB/s NVMe stripe with 20M objects:

| | Rate | 4×10⁹ objects |
|---|---|---|
| The userspace device scanner | 1,435,080 obj/s | 0.78 h |

That is **93% of the raw device**, from a single thread, because
`ext2fs_inode_scan` reads a block group's inode table in long sequential runs.

**The condition is the part to carry forward.** 93% of the device means the
scanner effectively *has* the device. That holds for an unmounted target, a
snapshot, or a failover partner's LUN. On a serving MDT the scan shares
bandwidth with the MDT's own I/O and gets proportionally less; on a snapshot it
pays copy-on-write indirection on top. Phase 2 does not fix this — the in-kernel
scanner reaches 99% of the same device, and the device is the ceiling either way.

## Built beyond what the HLD asked for

| | Why | Where |
|---|---|---|
| `lfind(8)` | the HLD names a device scanner but no command to drive it | 68160 |
| ZFS backend for the device scanner | the HLD's device scanner is ldiskfs only; a ZFS site would have had nothing | 68163 — LU-20613 |
| `lfs find --since`, `--changelog`, `--since-cookie` | the Changelog Input Scanner has no user without them | 68416–68420 — LU-20650 |

A changelog answers *what happened*, never what exists, so it reaches a user two
ways: `--since` treats the log as a candidate set and verifies each hit against
the live object, and `--changelog` reads the log and nothing else. The first
answers *as it is now*, the second *as it was recorded* — which is why an object
deleted during the window appears under one and cannot under the other.

## What Phase 1 still owes

| # | Item | Blocked by |
|---|---|---|
| 1 | **Object Stream binary format** | a decision that is not ours; evaluation not started. Blocks 2 and every cross-node use |
| 2 | **Merge / Split Filter Rule** — this is what covers a DNE filesystem | partly the format. Without it `lfind` does one target per invocation and nothing assembles the whole namespace |
| 3 | **Raw Write / Raw Read** — persist the stream and read it back | the format. It is also how multi-node merge works before any RPC exists |
| 4 | **Changelog Output Filter**, and the three indexes | nothing external — simply not started |

Also open on the epic and untouched: **LU-20602**, MDT-internal objects carrying
no LMA flag to mark them internal — which is why a target scan cannot cleanly
tell a user's object from the filesystem's own.

## Phase 2, deliberately untouched

Phase 2 is the in-kernel half, for 2.19: the OSD API Input Scanner, the
`circ_buf` kernel→userspace ring, and the bulk RPC modules on both sides. None
of it is submitted, and that is the plan rather than a slip.

Two things about it are known rather than assumed. The OSD scanner has been
**prototyped and measured** — 2.03M obj/s on ldiskfs with private per-shard
iterators, against 705k for the userspace scanner on the same warm cache. And
the ring has a working precedent in tree: `lustre/ofd/ofd_access_log.c` already
exports the OST access log kernel→userspace with exactly the `circ_buf` +
`.read` + `.poll` structure the HLD asks for, so it is a pattern to copy rather
than invent.

**One phrase in the epic needs qualifying.** The epic lists *"zero-copy lockless
ring-buffer kernel→userspace export"*. **Lockless, yes.** Zero-copy is
aspirational as written: the in-tree precedent uses `.read`, which copies once
from the ring into the user buffer. Genuine zero-copy needs `.mmap` of the ring
pages with head and tail in a shared control page — more work and more attack
surface, and worth measuring against the `read()` path before committing to it.
The requirements rank zero-copy export only Medium, below the scanner itself.

## What could go wrong

| Risk | Shape of it |
|---|---|
| **Nothing has landed** | Nineteen changes in review is the largest the series has been, and 2.18 is a deadline rather than a sequence. The argument for landing pieces one at a time gets stronger, not weaker, as the stack grows. |
| **The format decision is external** | Three of the four remaining Phase 1 items sit behind it, and its evaluation has not started. Nothing we do moves it. |
| **DNE is not covered** | Without Merge/Split, a device scan is per-target. Anyone testing `lfind` on a multi-MDT filesystem will find that out quickly, and it will read as a defect rather than as a module that is not written yet. |
| **Three sanity cases are unrun** | 160aa, 160ab and 160ac assert behaviour verified by hand on a cluster, but the test framework has never run them. The first autotest pass is where framework-level mistakes in them will surface. |

---

Sources: `Lustre_Find_Utility-High_Level_Design.pdf` v0.2 (Dilger 2026-04-03,
Blagodarenko 2026-08-08); LU-20462 and its nine subtasks; the Gerrit board as of
2026-08-26. Performance figures from
`measurements/cold-on-fast-storage-2026-08-16.md` and
`measurements/blockparse-2026-08-16.md`.
