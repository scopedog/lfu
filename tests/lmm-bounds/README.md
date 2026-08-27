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

## What is NOT covered

The harness exercises the validator, not the swab. It shows hostile geometry
is rejected before `layout_swab_lov_user_md()` is reached; it does not
instrument the swab itself. A real torn-EA read still wants the lab.
