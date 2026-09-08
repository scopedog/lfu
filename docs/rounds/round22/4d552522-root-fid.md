# 68156 `4d552522` — the hand-written root test ignored `f_ver`

2026-09-08, ninth of the seventeen. **Both of the comment's points are right,
and the drift it found is real.** Fixed; its suggested *mechanism* declined,
with a better one available.

## What was checked

`scan_classify()` decided the root with

    (fid_seq_is_root(seq) && lma->lma_self_fid.f_oid == FID_OID_ROOT)

while `fid_is_namespace_visible()` reaches it through `fid_is_root()`, which
is `lu_fid_eq(fid, &LU_ROOT_FID)` — and `lu_fid_eq()` is
`!memcmp(f0, f1, sizeof(*f0))` (`uapi/.../lustre_fid.h:363`), a whole-struct
compare. `LU_ROOT_FID` has `.f_ver = 0`. So a FID in `FID_SEQ_ROOT` with
`FID_OID_ROOT` and a **non-zero `f_ver`** was called namespace-visible here
and would not be by the MDT.

`f_ver` is genuinely in play: `scan_decode_lma()` byte-swaps and stores all
three fields off a device that may be in service, so this is not a field that
is structurally zero.

## What was done, and the one thing declined

**Declined:** moving `fid_is_root()` into the UAPI header. It would collide —
`lustre/include/lustre_fid.h:133` includes the UAPI header, so the server-side
definition would have to be deleted in the same patch, dragging a server
header into a utils change.

**Done instead:** spell the test as `fid_is_root()` *is*, using the two pieces
that are already public —

    lu_fid_eq(&lma->lma_self_fid, &LU_ROOT_FID)

which needs no header moved and is exact rather than approximate. The comment
now says that, in place of "fid_is_root() is a server-side helper, so the test
is spelled out", which was the sentence that licensed the drift.

## Measured

`tests/lift/root_fid.c`, driving the lifted `scan_classify()`:

| arm | unfixed | fixed |
|---|---|---|
| the root itself | VISIBLE | VISIBLE |
| **the root FID with `f_ver` set** | **VISIBLE** | INTERNAL |
| the echo client's root (`FID_OID_ECHO_ROOT`) | INTERNAL | INTERNAL |
| a normal FID | VISIBLE | VISIBLE |

**Unfixed 3 pass / 1 fail, fixed 4 / 0.** The third arm is the case the
spelled-out test was written for in the first place, and it is unchanged —
which is what makes this a narrowing and not a rewrite.

On a healthy MDT nothing moves: `lfind --device --paths` gives a
byte-identical 8-line answer before and after.

## The fixture was wrong first, again

`scan_classify()`'s second argument is `have_lma`, and passing `0` made all
four arms return `CLS_NO_LMA` — four failures that were all harness. Third
time today a first fixture has reported the code broken; the pattern is
always the same, and always caught by an arm that asserts the premise
instead of only the conclusion.
