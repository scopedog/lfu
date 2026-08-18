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

**Proposed fix.** Because both objects are already flagged-or-not by the same
function, and that function is the initial OI Scrub, "set it at creation" and
"have the initial LFSCK set it" are the same change: pass a compat flag instead
of `0` at `osd_scrub.c:1918`. Either reuse `LMAC_NOT_IN_OI` (no new constant,
existing consumers already skip on it, but its meaning is OI mapping rather
than namespace visibility) or add `LMAC_INTERNAL`.

Two questions for review:

1. Is everything `osd_ios_scan_one()` walks internal by construction? It is
   driven by `osd_lf_maps[]` over the OSD's own hierarchy, which suggests yes,
   but `ROOT` is scanned as well (`OLF_SCAN_SUBITEMS | OLF_HIDE_FID`), so it
   needs confirming that no user object can reach the flag.
2. The `-ENODATA` branch is not the whole upgrade path. At :1925 the `else`
   returns early on `LMAC_NOT_IN_OI` and otherwise only verifies the OI
   mapping, so a filesystem whose internal objects already carry an unflagged
   LMA needs the flag added there too.

Consumers should prefer the flag when present and fall back to the denylist
otherwise, since filesystems that have not run the new LFSCK will still have
unflagged objects.

---

**Evidence:** [`design-ldiskfs-scanner.md`](../design-ldiskfs-scanner.md) §5,
§5.1b, §17 · [`option-comparison.md`](../option-comparison.md) ·
[`design-osd-scanner.md`](../design-osd-scanner.md) §1

**Still open on the ticket:**

- [ ] `LMAC_NOT_IN_OI` vs a new `LMAC_INTERNAL` — for the reviewer to settle;
      decides whether the patch is one line or a UAPI change.
- [ ] Confirm nothing namespace-visible reaches `osd_ios_scan_one()` via the
      `ROOT` scan.
- [ ] Check whether osd-zfs has the same gap.
- [x] ~~Read the literal `update_log_dir` FIDs~~ — answered from the code
      instead: `osd_ios_uld_fill()` takes them from the entry name, so the
      normal sequence is by design.

---

## Comment for LU-20602

Paste-ready; the code trail above, minus the repo-internal references.

> Tracked down where these LMAs are written, and it makes the fix narrower than
> the description suggests.
>
> Both are written by the initial OI Scrub, in `osd_ios_scan_one()`
> (`osd-ldiskfs/osd_scrub.c:1876`), not at object creation. For
> `CONFIGS/mountdata`, the `CONFIGS` entry in `osd_lf_maps[]` uses
> `osd_ios_varfid_fill()`, which calls `osd_ios_scan_one()` with a NULL FID;
> `osd_get_lma()` returns `-ENODATA`, `lu_igif_build()` makes an IGIF from the
> inode number, and `osd_ea_fid_set(info, inode, &tfid, 0, 0)` at :1918 writes
> it with both flag words zero. That is the `[0xe:0x0:0x0]` in the description.
>
> For `/update_log_dir/*`, `osd_ios_uld_fill()` parses the FID out of the
> directory entry name — the llog id — and passes it to the same
> `osd_ios_scan_one()` and the same `osd_ea_fid_set(..., 0, 0)`. So the
> normal-sequence FIDs I flagged as possibly a second bug are by design: the
> directory is on `FID_SEQ_UPDATE_LOG_DIR` from the map, its contents inherit
> their llog FIDs. Please disregard that part of the description.
>
> Since both go through one function, and that function is the initial OI
> Scrub, "set the flag at creation" and "have the initial LFSCK set it" are the
> same change — pass a compat flag instead of `0` at :1918.
>
> Two things I could not settle from reading:
>
> 1. Is everything `osd_ios_scan_one()` walks internal by construction? It is
>    driven by `osd_lf_maps[]` over the OSD's own hierarchy, but `ROOT` is
>    scanned too (`OLF_SCAN_SUBITEMS | OLF_HIDE_FID`), so I would want
>    confirmation that no user object can reach the flag.
> 2. The `-ENODATA` branch is not the whole upgrade path: at :1925 the `else`
>    returns early on `LMAC_NOT_IN_OI` and otherwise only verifies the OI
>    mapping, so a filesystem whose internal objects already carry an unflagged
>    LMA needs the flag added there as well.
>
> Happy to post a patch once the flag question — reuse `LMAC_NOT_IN_OI` or add
> `LMAC_INTERNAL` — is settled. I have a lab that reproduces the leak and can
> show the before/after against `lfs find`.
