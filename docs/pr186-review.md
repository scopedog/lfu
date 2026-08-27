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

### Telling Artem how to fetch — and a correction we owed him

Checked before writing the instructions, and it mattered: **Gerrit's current
68156 PS9 still has `sr_gen` mid-struct.** The fix is local and unpushed, so
the follow-up above ("your FFI is now correct as written") was true of our tree
and *false of anything downloadable*. Corrected on the PR explicitly rather
than quietly: pull today and you need `sr_gen` in your mirror; pull after the
next patchset and you do not.

**The whole series is one fetch**, because it is a linear 16-commit stack and
the tip carries every ancestor:

```sh
git fetch https://review.whamcloud.com/fs/lustre-release refs/changes/20/68420/1
git checkout -b lfu FETCH_HEAD
```

Verified by actually running it into an empty repo — 16 commits down to
`5afbab284e`. The patchset number moves, so the durable form is

```sh
git ls-remote https://review.whamcloud.com/fs/lustre-release 'refs/changes/20/68420/*'
```

and take the highest numeric ref; `.../meta` is Gerrit's own bookkeeping.

**The series has no Gerrit topic set** (checked: `topic=(none)` on 68094, 68420,
68340). Setting one would let anyone fetch or view the series as a unit instead
of being told which change is the tip, and would group it in the web UI. Worth
doing on the next push — it costs nothing, since a topic can be set without a
new patchset.

68340, 68413 and 68414 sit on master rather than in the stack, and none is
needed to call `llapi_scan_device()`.

## Finding 2, resolved — and it was our documentation, not his misreading

Asked how Artem should fix the `LAZY_SIZE` check, and reading `scan_size()`
properly turned the finding around. **`llapi_scan_device.3` was wrong**, and
his code is a faithful implementation of it. The page said:

> For a regular file with a layout, `LLAPI_SCAN_SIZE` is **not set** ... When
> `trusted.som` answers, `LLAPI_SCAN_LAZY_SIZE` and `LLAPI_SCAN_LAZY_BLOCKS`
> say so.

The code has **two** paths to the non-lazy bits, and the second is the common
case:

1. a regular file with **no layout** (DoM, or never written) — answered from
   the object itself: `LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS`;
2. a striped file whose SOM is **`SOM_FL_STRICT`** — also
   `LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS`, because a strict SOM is
   authoritative and the MDT hands it to clients as a real size.

Only lazy or stale SOM sets the lazy bits. **`mdt.*.enable_strict_som` is on by
default**, so path 2 is most settled files — which upgrades the severity a lot:
his histogram was dropping the *majority* of the filesystem, skewed exactly the
wrong way, since a file with a strict SOM is one that has been sitting
untouched. That is the cold data the dashboard exists to show.

Man page rewritten in 68156 to describe both paths and to say plainly that a
consumer wanting a size should test `LLAPI_SCAN_SIZE` and `LLAPI_SCAN_LAZY_SIZE`
together. `groff -man` clean. Artem given the exact patch, plus two optional
notes: the two bits are real information (exact vs approximate) if he wants to
keep them apart, and `sr_blocks` is the more honest number than `sr_size_bytes`
for "how much space is cold" on sparse or DoM files.

**Both findings against this PR ended up being ours.** One was a layout that
broke our own append-only promise; the other was a man page that documented the
opposite of what the code does. The consumer wrote correct code against both.
That is the argument for having a first consumer before landing, and for
reading the implementation rather than the prose when answering "how do I fix
this".

Verified after the doc fix: 16 commits, 16 Change-Ids, base `5afbab284e`,
checkpatch **0 errors total** across all 16, build rc=0 with zero diagnostics.
