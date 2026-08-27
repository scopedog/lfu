# TheLustreCollective/lustre PR #186 — the first consumer of llapi_scan_device()

Artem's `lfu-dashboard` branch (head `25577fd5`), an OTel MDT file-age histogram
that calls `llapi_scan_device()` through hand-written Rust FFI. Reviewed
2026-08-27. This is the first code outside our series to use the API, so it is
also the first real test of the API's compatibility story — and it fails it.

## 1. `sr_gen` breaks the append-only promise, and this PR is already on the wrong side of it

`otel-lustre/src/metrics/age.rs` mirrors `struct llapi_scan_rec` field by field.
The mirror matches the header **the PR itself ships** — which has no `sr_gen`.
Our current tree has it, inserted between `sr_ino` and `sr_parent_fid`:

    __u64  sr_ino;
    __u32  sr_gen;              <-- added in 68156 PS7 (the 2026-08-24 push)
    struct lu_fid sr_parent_fid;

Checked against every published patchset: **68156 PS1–PS6 have no `sr_gen`;
PS7 onward do.** Artem branched from PS6 or earlier.

Measured offsets, x86-64 (`docs/` has the throwaway program):

| field | PR's base | current | |
|---|---|---|---|
| `sr_ino` | 168 | 168 | same |
| `sr_parent_fid` | 176 | 184 | **+8** |
| `sr_linkea` | 192 | 200 | **+8** |
| `sr_linkeasize` | 200 | 208 | **+8** |
| `sr_class` | 204 | 212 | **+8** |
| `sr_lma_compat` | 208 | 216 | **+8** |
| `sr_lma_incompat` | 212 | 220 | **+8** |
| `sizeof` | 216 | 224 | |

**This is not latent — it is a silent total failure the moment they rebase.**
`age_cb()` does:

```rust
if (rec.sr_valid & LLAPI_SCAN_CLASS) != 0 && rec.sr_class != LLAPI_SCAN_CLS_VISIBLE {
    return 1; // filtered
}
```

- `LLAPI_SCAN_CLASS` is set **unconditionally** on every emitted device-scan
  record (`liblustreapi_scan_device.c:531`), not gated on `sp_want`, so the
  guard is always live.
- Their `sr_class` would read offset 204, which in the current struct is the
  **upper four bytes of the `sr_linkea` pointer**.
- `scan_linkea()` is also called unconditionally
  (`liblustreapi_scan_device.c:560`), and most namespace-visible MDT objects
  have a `trusted.link` xattr, so that pointer is **not NULL** — its top half is
  a nonzero address prefix.

So every regular file gets filtered, every bucket totals zero, and the dashboard
reports *"no cold data"* with no error and no crash. The most expensive kind of
wrong answer.

**The uncomfortable half is ours.** `Documentation/man3/llapi_scan_namespace.3`
says, of `sr_size`:

> holds the size of the record the scanner filled, so a consumer built against
> an older definition of the structure continues to work; **fields are only ever
> appended.**

We inserted one in the middle. Nothing has landed upstream, so pre-landing
churn is defensible — but the promise is already written down, a consumer is
already built against it, and `sr_size` cannot rescue a mid-struct insertion:
it tells a consumer how much was filled, never that the layout moved.

Worth deciding, and it is a real choice, not a formality:
- **move `sr_gen` to the end of the struct**, honouring the promise as written;
  it costs the nice adjacency with `sr_ino` that its comment relies on; or
- **keep it, and say plainly that the append-only guarantee begins at landing**,
  which means telling every early consumer to track the series rather than pin.

Either way Artem needs to know now, because rebasing is what detonates it.

## 2. Files with an authoritative size are dropped from the histogram

```rust
let size = if (rec.sr_valid & LLAPI_SCAN_LAZY_SIZE) != 0 {
    rec.sr_size_bytes
} else {
    accum.no_size += 1;
    return 0;
};
```

The PR body reads this as *"size not yet flushed to MDT"*. That is only one of
the two ways `LLAPI_SCAN_LAZY_SIZE` can be clear. `scan_size()`
(`liblustreapi_scan_device.c`) sets **`LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS`**,
not the lazy bits, for a regular file with no LOV xattr — nothing is striped out
from under it, so the target's own size *is* the file's. DoM files and unstriped
files land there.

Those are exactly the files whose size is known most reliably, and they are
being counted into `no_size` and their bytes discarded. The test should be
`sr_valid & (LLAPI_SCAN_SIZE | LLAPI_SCAN_LAZY_SIZE)`.

The man page is explicit — *"Neither bit set means the size is not known to the
target"* — so this is a misreading rather than a doc gap. But it is the second
consumer-facing trap in one struct, which says something about how much of this
API's meaning lives in the valid-bits.

## 3. What checks out

Worth stating, because it is most of the FFI:

- All four constants exact: `TYPE 0x4000`, `ATIME 0x80`, `LAZY_SIZE 0x10000`,
  `CLASS 0x01000000`.
- `llapi_scan_param` mirror is field-for-field correct, padding included.
- `llapi_scan_stats` mirror correct, and `ss_class: [u64; 6]` is right —
  `LLAPI_SCAN_CLS_MAX` is 6 (VISIBLE, INTERNAL, OST_OBJ, AGENT, NO_LMA, BAD).
- `sp_max_depth: 0` is correct for unlimited; `sp_thread_count` semantics right.
- Our stats writeback is properly defensive: it clamps to the caller's
  `ss_size` and copies no more (`liblustreapi_scan_device.c:976-984`), so their
  larger-or-equal buffer is safe.

## 4. The systemic note

The PR never reads `sr_size` — the one field we provide for exactly this
problem. A consumer that checked it could at least detect a shorter record. It
still would not catch a mid-struct insertion, which is the point: **`sr_size`
buys forward compatibility only if fields are appended.** If we want
hand-written FFI consumers to be viable at all, the API needs either a stable
layout or a generated binding; asking people to transcribe a moving struct by
hand will keep producing this.

---

## Resolved 2026-08-27: `sr_gen` moved to the end of the struct

The user's call, and the right one: honour the promise in the layout rather
than ask every consumer to track a moving struct.

`sr_gen` now sits after `sr_lma_incompat` — the end of the struct **as 68156
defines it** — with the later changelog block appended after that. Verified by
`offsetof` against the real header, not a transcription:

| field | 68156 PS6 | now |
|---|---|---|
| `sr_ino` | 168 | 168 |
| `sr_parent_fid` | 176 | 176 |
| `sr_linkea` | 192 | 192 |
| `sr_linkeasize` | 200 | 200 |
| `sr_class` | 204 | 204 |
| `sr_lma_compat` | 208 | 208 |
| `sr_lma_incompat` | 212 | 212 |
| `sr_gen` | — | 216 |

**Every PS6 offset restored**, growth append-only, `sizeof` 216 → 304.

The pleasing part: **PR 186's FFI is now correct exactly as written**. The fix
did not just prevent a future break, it removed the one that was already
loaded. Artem was told so in a follow-up review; finding 2 (the `LAZY_SIZE`
misreading) is unaffected and still stands.

Where it landed: the comment on the field says only why it is where it is; the
argument is in 68156's message. `sr_gen` has exactly one user
(`liblustreapi_scan_device.c:446`), so nothing else moved.

Verified: 16 commits, 16 Change-Ids, base `5afbab284e`, all subjects <=50,
build rc=0 with zero `-Wall -Werror` diagnostics, checkpatch 0 errors on all 16
(68156 goes 2649 -> 2654 lines checked, findings unchanged). The commit-msg
hook rejected a 71-column line on the first attempt, which is the hook doing
its job.

### The two stale inline threads, closed

The summary follow-up corrected finding 1, but the **inline** comments on
`age.rs:77` and `:174` still read *"8 bytes off once you rebase"*, which our
own change had just made false. A reader scrolling the diff sees those threads
without necessarily reading the review body. Both got a short reply saying they
are superseded and that the code is correct as written; the line 183
(`LAZY_SIZE`) thread was deliberately left alone, because that one still
stands.

**Worth generalising: fixing a problem on our side does not retract what we
already said about it on someone else's.** A review comment is a claim with a
timestamp, and when the ground moves under it the thread has to be closed
explicitly — a correction posted somewhere else in the PR does not reach the
person reading the diff.
