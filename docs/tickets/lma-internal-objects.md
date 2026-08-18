# LU-20602: LMA flag for MDT-internal objects

**Filed 2026-08-18** as **LU-20602**. Requested by Andreas Dilger the same day,
in review comments kept under `docs/local/` (not published).

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

**Proposed fix.** Add a new compat flag — `LMAC_INTERNAL`, "not part of the
user namespace" — and set it at `osd_scrub.c:1918`. Because both objects are
flagged-or-not by the same function, and that function is the initial OI Scrub,
"set it at creation" and "have the initial LFSCK set it" are the same change: a
compat flag instead of `0`.

**Not `LMAC_NOT_IN_OI`.** That flag is a control, not a label, and these objects
need the behaviour it suppresses:

- It gates the OI insert in the function being patched. The `else` branch of
  `osd_ios_scan_one()` returns at :1926 on `LMAC_NOT_IN_OI`, before the
  fallthrough to `osd_oi_lookup()` (:1954) and
  `osd_scrub_refresh_mapping(..., DTO_INDEX_INSERT, ...)` (:1959). Setting it
  would stop the next initial scrub inserting, verifying or repairing these
  objects' OI mappings.
- They do have OI mappings — the same function inserts them. The
  `update_log_dir` entries are on normal sequences, so `osd_oi_lookup()` reaches
  `__osd_oi_lookup()`; `mountdata`'s IGIF does too whenever `od_igif_inoi` is 1,
  which is the normal case (cleared only on an upgrade path, `osd_scrub.c:2696`).
- It is evidence in duplicate-FID detection: `osd_oi.c:729` treats
  `!(lma_compat & LMAC_NOT_IN_OI) && lu_fid_eq(...)` as two objects sharing one
  FID and errors. Flagging these would disarm that check for them.

**Compat, not incompat.** An unknown incompat bit fails `LMA_INCOMPAT_SUPP` and
the object is rejected as unsupported. A compat bit is ignored by old readers,
which is what a classification hint wants: old scanners keep their denylist, new
ones use the flag.

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

- [x] ~~`LMAC_NOT_IN_OI` vs a new `LMAC_INTERNAL`~~ — resolved from the code:
      a new compat flag. `LMAC_NOT_IN_OI` gates the OI insert these objects
      need. Confirm with the reviewer, but the patch can be written on it.
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
> On which flag: I think this needs a **new compat flag** (`LMAC_INTERNAL`, "not
> part of the user namespace") rather than reusing `LMAC_NOT_IN_OI`. The latter
> is a control rather than a label, and these objects need what it suppresses.
> The `else` branch of `osd_ios_scan_one()` returns at :1926 on
> `LMAC_NOT_IN_OI`, before the fallthrough to `osd_oi_lookup()` at :1954 and
> `osd_scrub_refresh_mapping(..., DTO_INDEX_INSERT, ...)` at :1959 — so setting
> it would stop the next initial scrub inserting or repairing these objects' OI
> mappings, and they do have mappings, inserted by that same code. The
> `update_log_dir` entries are on normal sequences and so reach
> `__osd_oi_lookup()`; `mountdata`'s IGIF does too whenever `od_igif_inoi` is 1.
> `osd_oi.c:729` also uses the absence of that flag as evidence when detecting
> two objects sharing a FID, and flagging these would disarm the check for them.
>
> Compat rather than incompat, so that an old reader ignores it instead of
> rejecting the object through `LMA_INCOMPAT_SUPP`.
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
> Happy to post a patch on `LMAC_INTERNAL` if that reading is right. I have a
> lab that reproduces the leak and can show the before/after against
> `lfs find`.
