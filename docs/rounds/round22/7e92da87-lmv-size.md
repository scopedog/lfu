# 68156 `7e92da87` — the two scanners disagree on `sr_lmvsize`, and the shard area is stale

2026-09-08, third of the seventeen. **Both halves verified; the leak fixed and
measured, the size disagreement documented rather than papered over.**

## What the two scanners answer for one directory

A 4-stripe directory, `lum_stripe_count` 4 either way:

| | size | `lum_objects[]` |
|---|---|---|
| `llapi_scan_namespace()` | 144 | the four shard FIDs |
| `llapi_scan_device()` | 48 | nothing |

The namespace side is `LL_IOC_LMV_GETSTRIPE`'s own sizing — `llite/dir.c:2264`
allocates `lmv_user_md_size(stripe_count, LMV_USER_MAGIC_SPECIFIC)`, fills
`lum_objects[i]` per shard and copies out that many bytes — so
`llapi_scan_lmv_size()` matching it is right, not a mistake.

The device side deliberately has no shards: naming one needs its MDT index,
which is an FLD lookup a scan of an unmounted target has no client to make.
The header has said so since 68094.

## The defect: the shard area keeps the last object's bytes

`scan_lmv_to_user()` cleared only `lmv_user_md_size(0, LMV_USER_MAGIC)` — 48
bytes, the header. `sw_lmv` is one 4096-byte buffer per worker, reused for
every object, so everything past the header is whatever the last one left.

Measured with `tests/lift/lmv_stale.c`, which drives the real function (cut
out of the tree by `lift.py`) over a foreign directory with a 2048-byte value
and then a 4-stripe directory through the same buffer:

    FAIL  the shard area a count-sized read touches is clear
          96 of 96 shard bytes still hold the previous object's LMV

**96 of 96.** A consumer sizing `lum_objects[]` by `lum_stripe_count` — which
`lmv_dump_user_lmm()` does, both in its `obdindex` loop and under the
`VERBOSE_OBJID` default it picks for a non-`LMV_USER_MAGIC` magic — reads a
previous object's opaque foreign value as shard FIDs. `rec->lfsr_lmv` points
straight at `sw_lmv`, so a callback sees it directly; nothing in tree feeds a
scan record to that function yet, which is what keeps this latent.

**Unfixed 3 pass / 1 fail, fixed 4 / 0.**

## What was done, and what was declined

**Fixed:** the clear now reaches as far as a count-sized read can, bounded by
the room before a count read off a device measures anything:

    stripes = __le32_to_cpu(md->lmv_stripe_count);
    room = (outlen - lmv_user_md_size(0, LMV_USER_MAGIC)) /
           sizeof(struct lmv_user_mds_data);
    memset(out, 0, lmv_user_md_size(stripes < room ? stripes : room,
                                    LMV_USER_MAGIC_SPECIFIC));

**Fixed:** `sw_lmv` is a union of `lmv_user_md`, `lmv_foreign_md` and the byte
array, as the comment asked. A bare `char[]` carries neither structure's
alignment while the call site casts to both — and `lmv_foreign_md` is not
packed, so it really does want 4.

**Declined, with the reason:** reporting
`lmv_user_md_size(lum_stripe_count, LMV_USER_MAGIC_SPECIFIC)` to make the two
agree. That would claim 96 bytes of shard FIDs the scan does not have and
hand back zeroes as answers — a fabricated `lum_fid` of `0:0:0` on MDT0000
for every stripe, which is worse than a short buffer a consumer can measure.
`sr_lmvsize` means the bytes filled, and the fix is to say so where a
consumer will read it: the record's own comment in `lustreapi.h` and a
paragraph in `llapi_scan_device.3`, both stating that `lum_objects[]` is
measured by `sr_lmvsize` and never by `lum_stripe_count`.

## Two traps this one walked into

**A form feed in the man page.** The first version of the roff was written
from a non-raw Python string, so `\fI` became an actual form-feed byte and
the page rendered `lmv_user_md_size(IcountR, BLMV_USER_MAGIC_SPECIFICR)`.
Caught by rendering the page rather than by reading the diff. The tree is now
swept for stray form feeds and has none.

**A comment naming a field that does not exist yet.** The fixup landed on
68156 without conflict — which was the warning, not the reassurance. The
`sr_` → `lfsr_` rename is a later commit, so at 68156 the new comment and
man-page text named `lfsr_lmvsize` while the struct member beside it was
`sr_lmvsize`. Gerrit reviews each change on its own, so that had to be the
old spelling there and the new one at the tip: the text was rewritten inside
68156 and the rename commit amended to carry it forward. Checked both
directions — no `lfsr_` in 68156's header or man page, none left as `sr_` at
the tip.

## Left open, for the record

Whether a device scan should learn to emit shard FIDs at all is not this
comment's question and is already answered in the header: it cannot fill
`lum_mds` without an FLD lookup. If that ever changes, the clear becomes
redundant and harmless.
