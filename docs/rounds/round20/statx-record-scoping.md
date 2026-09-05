# Embedding `struct statx` in `llapi_scan_rec` — scoping, not a recommendation

adilger, `613572f2` on `lustreapi.h:599`:

> Would it make sense to piggy-back on `struct statx` here? That would
> avoid one level of conversion for the current ioctl scanner and allows
> for future expansion ... without inventing a gratuitously similar data
> struct here.

Written up so the size can be judged before the design is argued.

## It is not one conversion. It is a round trip.

    MDT ioctl  ->  lmd->lmd_stx        (lstatx_t: already a statx)
               ->  rec->sr_mode/uid/atime/...   (scan_rec_mdt)
               ->  lmd->lmd_stx        (find_rec_to_lmd)
               ->  the predicates

`lfs find` over a device scan converts a statx into flat fields and then
straight back into a statx, because every predicate below
`find_decide()` reads `lmd_stx`. Measured:

| function | total | statx-derived |
|---|---|---|
| `scan_rec_mdt()` (producer) | 114 lines | 17 |
| `find_rec_to_lmd()` (consumer) | 119 lines | 26 |

So ~43 lines exist only to take a statx apart and put it back together.
Embedding it deletes both halves rather than one, which is **more** than
the comment claims.

## And it is where a real defect lives

    rec->sr_atime = lmd->lmd_stx.stx_atime.tv_sec;

`sr_atime` is a bare `__s64`, so `tv_nsec` is dropped in that copy — on
all four timestamps. That is adilger's `b3ce6f88`, which he marks a
**defect** and ties to LU-1158 converting the tree to nanoseconds.

**`613572f2` and `b3ce6f88` are one problem.** Embedding statx fixes the
nanosecond loss for free, because the conversion that loses them stops
existing. Fixing `b3ce6f88` on its own means widening four fields and
touching the same sites anyway — most of the cost with none of the
simplification.

## "Gratuitously similar" is measurable

Eleven `sr_valid` bits are one-to-one with `STATX_*`:

    MODE  NLINK  UID  GID  SIZE  BLOCKS  ATIME  MTIME  CTIME  BTIME  TYPE

`find_rec_to_lmd()` already translates between the two masks by hand.

## The size

    references to the eleven statx-shaped fields      85
    references to the twelve duplicated mask bits    165
    consumers of llapi_scan_rec outside this series    0

By file, the fields:

| file | refs |
|---|---|
| `liblustreapi_pfind.c` | 21 |
| `include/lustre/lustreapi.h` | 17 |
| `liblustreapi_scan.c` | 15 |
| `liblustreapi_scan_device.c` | 14 |
| `liblustreapi_scan_changelog.c` | 11 |
| `llapi_scan_test.c` | 3 |
| `libscan_ldiskfs.c` | 2 |

Three producers fill the attribute block — the namespace scanner (13
assignments), the device scanner (13) and the changelog resolver (10) —
and one consumer reads it. The two backends (`libscan_ldiskfs.c`,
`libscan_zfs.c`) barely touch these fields: they fill
`struct llapi_scan_obj`, which is internal and unaffected.

**Nothing outside the series consumes the record**, so the blast radius
is the eleven files above and their four man pages.

## What it would actually take

1. Replace the eleven flat fields with one embedded `lstatx_t`, keeping
   `stx_mask` as their validity and dropping the eleven duplicated
   `sr_valid` bits. (`sr_valid` stays for the ~20 bits statx has no
   place for: FID, LAYOUT, LMV, LINKEA, PROJID, MDT_INDEX, HSM, CLASS,
   GEN, PARENT, OWNER, EVENT\*.)
2. `scan_rec_mdt()`: delete the 17 statx-derived lines, assign
   `rec->sr_stx = lmd->lmd_stx` — the ioctl already produced it.
3. `find_rec_to_lmd()`: delete the 26 statx-derived lines and the mask
   translation, assign `lmd->lmd_stx = rec->sr_stx`.
4. The device backend and the changelog resolver build a statx instead
   of flat fields — they start from `struct stat`/on-disk inodes either
   way, so this is a rename of the destination, not new logic.
5. Man pages: four of them, ~30 lines of field tables.
6. Tests: `llapi_scan_test.c` (16 mask refs, 3 field refs),
   `llapi_scan_device_test.c` (7).

**Estimate: a day, and it is a net deletion in the two hot functions.**
Mechanical rather than delicate — the compiler finds every site, and
the existing tests cover the result.

## What it costs, honestly

- **The record embeds a Lustre UAPI type.** `lstatx_t` is Lustre's own
  copy of `struct statx` in `lustre_user.h`, not libc's. Defensible —
  the MDT already speaks it — but it is not quite "just use statx".
- **Two masks instead of one.** `stx_mask` for the statx part,
  `sr_valid` for the rest. Arguably clearer, arguably worse; it is a
  taste call and he should make it.
- **`LAZY_SIZE`/`LAZY_BLOCKS` have no statx counterpart** and are
  load-bearing: they carry the strict-versus-lazy distinction the device
  scanner depends on, and the reason `scan_size()` exists. They stay in
  `sr_valid` and now qualify a field living in `stx_size`, which is
  slightly awkward and worth saying out loud rather than discovering.
- **It moves `0572e1bb`/`ddf8a5d2`.** With `stx_mask` in the record, his
  mask-versus-size argument gets its natural vehicle — so answering this
  one probably answers those two, and they should be decided together
  rather than in sequence.

## Recommendation

Do it, if it is done before 2.18 ships. It removes more code than it
adds, closes a defect he has already flagged, and the alternative
(widening four timestamps in place) pays most of the cost for none of
the benefit. The argument against is timing, not design: he is mid-series
and three of his other comments bear on the same struct.

Not started. This is scoping only.
