# `find_lmm_fits()` bounds harness

Verifies the fix for the out-of-bounds write found by 68159's AI review
(2026-08-27): `layout_swab_lov_user_md()` ran **before** `find_lmm_fits()`,
so a torn composite layout read off a live target was walked by
`lcm_entry_count` and stored through `lcme_offset` with nothing bounding
either.

Needs no lab. Extract the function under test and compile:

```sh
L=~/projects/lustre/lustre-scanfid
awk '/^static bool find_lmm_fits/,/^}/' $L/lustre/utils/liblustreapi_pfind.c > flf_body.inc
gcc -I $L/include -I $L/include/uapi -o lmmfuzz lmmfuzz.c && ./lmmfuzz
```

Swap `flf_body.inc` for the pre-fix version to run the control.

## Results, 2026-08-27

Fixed validator: **14 of 14 as expected**, including rejection of
`lcm_entry_count = 65535` and `lcme_offset = 0xfffff000` in **both byte
orders**, before any swab can run — which is the write closed.

Pre-fix validator, same buffers: it **accepts** two cases the fixed one
rejects — `lcme_offset == size` with `lcme_size 0`, and an offset leaving
less than `sizeof(struct lov_user_md_v1)` in the buffer. Those are the
48-byte over-read, and the control proves they were reachable.

**One control line needs reading carefully rather than at face value.** The
pre-fix validator also rejects *well-formed byte-swapped* layouts. That is not
a defect in the old code: in the old call order the swab ran first and had
already put the buffer in host order, so the validator never saw a swapped
one. The harness compares two functions that sat at different points in the
pipeline, so only the two over-read rows are a like-for-like regression.

## The foreign magic, 2026-08-28

68159 PS10's AI review found a second thing in the same function: the swap
detection accepted a byte-swapped `LOV_USER_MAGIC_FOREIGN`, but
`layout_swab_lov_user_md()` only ever swabs a top-level V1, V3 or COMP_V1
and returns untouched on a foreign one. So on a big-endian host a foreign
layout -- an HSM-released or PCC file -- passed the validator, had
`lmd_lmmsize` set, and reached `find_check_foreign()` still in the target's
byte order, where `lfm_magic` did not compare equal and the answer was "not
foreign". `--foreign` missed every such file; `--stripe-count` read bytes of
`lfm_value` as a count.

Three rows added for it. Fixed validator: **17 of 17 as expected** --
a host-order foreign layout is still a layout, one whose buffer is short is
not, and a byte-swapped one is refused so that it takes the no-layout path.

Pre-fix validator, same buffers: it **accepts** the byte-swapped foreign
layout. That row is the defect, and it is like-for-like -- both versions run
at the same point in the pipeline for this case, unlike the swapped-composite
rows above.

One thing the harness had to be taught: `lfm_length = 8` is rejected by both,
because the entry guard refuses a buffer shorter than a `lov_user_md_v1` and
`find_rec_to_lmd()` refuses one before that. A real foreign EA (`lov_hsm_md`)
is longer, so the cases use 64.

## What is NOT covered

The harness exercises the validator, not the swab. It shows hostile geometry
is rejected before `layout_swab_lov_user_md()` is reached; it does not
instrument the swab itself. A real torn-EA read still wants the lab.
