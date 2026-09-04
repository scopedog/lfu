# adilger's review of 68094 — 15 comments, and why I stopped

**2026-09-03 22:30.** Andreas Dilger reviewed **68094**, the foundational
change of the series (`llapi: namespace scanner API`), leaving 15
comments — and said so explicitly:

> Just going through the series.  Some comments are just ideas at this
> point, and I'm not sure whether I'll have the same thoughts as I get to
> the end.

So more are coming.  He has one comment each on 68231, 68616 and 68617
so far and none yet on the rest.

**I have not acted on any of them.**  Most are design questions about the
shape of a public API, and several interact, so answering one wrongly
costs the others.  That is your call, not mine.

## The four that would restructure the series

### 1. Size-based versioning vs. mask negotiation (`ca388b67`, `0572e1bb`, `ddf8a5d2`, `78bca5f4` — four comments, one argument)

> Shouldn't the size of the buffer be largely irrelevant, and rather the
> "understanding" and usage of the fields in the struct be determined by
> the mask of fields being requested?  Otherwise, an application built
> against a larger library version would not be able to run on an older
> Lustre installation even though it is only requesting fields that the
> old library understands.
>
> That essentially breaks interoperability every time struct grows in
> size and puts pressure on _not_ adding new struct fields.

He is describing the exact rule the API has today: `sp_size >
sizeof(spl)` is refused, so a **newer caller against an older library is
rejected outright**, even asking only for old fields.  He proposes
`sr_valid`/`sp_want` negotiate instead, `OBD_CONNECT_*` style — the
library answers the subset it understands.

This is the single biggest comment.  It would rewrite the parameter
handling in all five entry points and change what `sr_size`/`sp_size`
mean — and much of tonight's work touched exactly those lines.

### 2. Bulk records instead of a callback per object (`ec554e54`, `91d84157`)

> Returning a single record for each call is OK for POSIX namespace
> scanning (which is inherently single-item), but it would be inefficient
> for the ldiskfs scanner if it is reading 1MiB chunks of the MDT inode
> table ... rather than millions or billions of callbacks.

An array-filling API beside the callback one.  This is the consumer
interface for the whole LFU, so it reaches every scanner and `lfs find`.

He also asks whether consumer and scanner thread counts can differ, and
whether they are the same threads.

### 3. Reuse `struct statx` rather than a bespoke record (`613572f2`)

> Would it make sense to piggy-back on `struct statx` here?  That would
> avoid one level of conversion for the current ioctl scanner and allows
> for future expansion (with the Lustre-specific fields beyond the 0x100
> offset) without inventing a gratuitously similar data struct.

This would also answer the nanosecond point below for free.

### 4. FlatBuffers / Cap'n Proto (`ca388b67`, second half)

> I thought we would use something like FlatBuffers or Cap'n Proto for
> the LFU interface so that it doesn't need to allocate and copy structs
> that contain every possible field even when the majority are not used?

This is the **wire-format question held on 2026-08-19** and decided off
the meeting as not ours.  The maintainer now expects it in this API.
That needs settling before the record's shape is settled.

## The one marked (defect), and it is timely

`b3ce6f88` — **nanosecond timestamps**:

> We are _just_ adding in nanosecond timestamp support for Lustre in
> another patch series ... so it seems negligent to build a new API that
> does not allow nanoseconds to be handled.

Verified: `LU-1158 compat: add nanosecond timestamp helpers` is already
in the tree.  Our record carries second-resolution times.  Building a new
public API without nanosecond capability, while the tree is being
converted to it, is the kind of thing that blocks a series — and the fix
is not local, because it interacts with 3 above.

## The two mechanical ones — real, but premature

- `aca4315e`, `129ce4b5`: **`sr_` and `sp_` collide.**  Confirmed:
  `sr_` in `lustre_net.h`, `lustre_quota.h`, `lustre_sec.h`,
  `seq_range.h`; `sp_` in `md_op_spec`.  He suggests `lfsr_`/`lfur_`.
  A rename touches every file in the series and every test — worth doing
  **once**, after the struct's shape is settled, not before.
- `2294e6ed`: **odd number of `__u32`s before `sr_lmm`.**  Measured:
  seven `__u32`s run from `sr_mode` to `sr_lmvsize`, so the compiler
  inserts **4 hidden bytes** before `sr_lmm` at offset 136.  The fix
  (an explicit pad, or reordering) is two lines and changes no offsets —
  but it is cosmetics on a struct that may not survive 1 and 3.

## The rest

| id | comment | note |
|---|---|---|
| `635bad20` | "Presumably `statx()` and not regular `stat()`?" in the message | wording; trivial once the message is next touched |
| `bd8f3964` | the POSIX scanner's FID built from a filename risks colliding with real FIDs; could it be IGIF from the inode number? | see [[lfu-posix-scanner]] — this is the same objection that module already raised against itself |
| `e586539f` | push `STATX_PROJID` upstream (LU-12480) to drop the extra ioctl | future work, not this series |
| `343d8cab` | could the test auto-detect instead of being told? | small, but in a file the above may reshape |

## Why nothing is fixed here

Every one of the first four changes what a record *is*.  Doing any of
them tonight would mean rewriting the parameter handling I have been
correcting all evening, and doing it against a guess at which of the four
you want — when three of them (mask negotiation, statx reuse, a
serialisation format) are alternative answers to the *same* question, and
the fourth (bulk return) changes the call shape they all share.

They also arrive with the maintainer saying he may not hold the same
view by the end of the series.

**This needs your decision before any of it is worth building.**

Meanwhile the local round-20 work stands: 18 changes, 18 Change-Ids,
builds clean, lab green, nothing pushed.
