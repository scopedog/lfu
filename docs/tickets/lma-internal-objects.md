# LU-20602: LMA flag for MDT-internal objects

**Filed 2026-08-18** as **LU-20602**. Requested by Andreas Dilger the same day
([comments](../andreas-comments-2026-08-18.txt), final paragraph; item C1 in
[the response plan](../andreas-response-2026-08-18.md)).

Type Improvement · Priority Minor · Components osd-ldiskfs, osd-zfs, lod,
lfsck · Affects 2.17 (observed; code inspected at v2_17_55) · Related LU-20462.

Kept here as the source text and the evidence trail; the ticket is the record
of what was filed, not of what is still to be decided — the open items below
travel with the ticket.

---

## Summary

MDT-internal objects carry no LMA flag marking them internal

## Description

A scan that enumerates objects without namespace context classifies each one
from `trusted.lma` and its FID, using the ladder in `osd_scrub_get_fid()` /
`osd_iit_iget()`. Three MDT-internal objects pass it and come out user-visible:

| Object | FID | `lma_compat` | `lma_incompat` |
|---|---|---|---|
| `/CONFIGS/mountdata` | `[0xe:0x0:0x0]` — IGIF, seq = its own inode number | 0 | 0 |
| `/update_log_dir/[0x200000400:0x1:0x0]` | normal sequence | 0 | 0 |
| `/update_log_dir/[0x200000401:0x1:0x0]` | normal sequence | 0 | 0 |

`LMAC_NOT_IN_OI` is set on the OI and sequence directories (`osd_compat.c`,
`osd_oi.c`) but not on objects created through `local_storage.c`, nor on
`mountdata`; and `fid_is_namespace_visible()` accepts both an IGIF and a normal
sequence, so FID range does not separate them either. `FID_SEQ_UPDATE_LOG` /
`FID_SEQ_UPDATE_LOG_DIR` would classify the update logs correctly, but the
objects observed are not on those sequences — whether that is expected is a
question for the reviewer.

Observed on RHEL 9.7, Lustre 2.17, `testfs-MDT0000` on `/dev/vdb`, 1024-byte
inodes, MDT mounted and serving: inodes read straight from the inode table, FID
set compared against `lfs find` + `lfs path2fid`. Exactly these three appear as
extras at both 173 and 509 objects — zero missing, and the leak is bounded
rather than proportional. (Three further extras are `.lustre`, `.lustre/fid`
and `.lustre/lost+found`, which are genuinely visible and merely hidden from
`lfs find`.)

**Impact.** Every out-of-namespace scanner needs a hand-maintained denylist of
internal inode numbers, tracking every future layout change, in every consumer.
A flag on the object is durable; a denylist is not.

**Proposed fix.** Set a compat flag in `trusted.lma` at creation —
`local_object_create()` / `__local_file_create()` in
`obdclass/local_storage.c`, and wherever `mountdata`'s LMA is first written.
Either reuse `LMAC_NOT_IN_OI` (no new constant, existing consumers already skip
on it, but its meaning is OI mapping, not namespace visibility) or add
`LMAC_INTERNAL`. For existing filesystems, have the initial LFSCK set the flag
when these objects are opened or checked. Consumers should prefer the flag when
present and fall back to the denylist otherwise, since filesystems that have
not run the new LFSCK will still have unflagged objects.

---

**Evidence:** [`design-ldiskfs-scanner.md`](../design-ldiskfs-scanner.md) §5,
§5.1b, §17 · [`option-comparison.md`](../option-comparison.md) ·
[`design-osd-scanner.md`](../design-osd-scanner.md) §1

**Still open on the ticket:**

- [ ] Read the literal FIDs of the two `update_log_dir` objects off the lab MDT
      — recorded above as prose, and the `FID_SEQ_UPDATE_LOG` question needs the
      exact values. Post them to LU-20602 when measured.
- [ ] `LMAC_NOT_IN_OI` vs a new `LMAC_INTERNAL` — for the reviewer to settle.
- [ ] Check whether osd-zfs has the same gap.
