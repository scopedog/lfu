# Round 11's lab: what it can and cannot prove

Built 2026-08-27 on the user's offer. `lfu-r11-srv` + `lfu-r11-cli`,
us-central1-a, 4 MDTs, ldiskfs. The tree is the 16-commit stack **plus 68340
cherry-picked on top** — checked locally first, it applies cleanly, so the
combined tree is what a landed series will actually look like.

## Why another lab at all

The DNE lab earlier today ran against a tree that has since changed. Diffing
the exact patches it built against the current ones: seven patch files differ,
but comparing **only the changed lines**, six differ by nothing — pure
line-number shift. The real post-lab changes are the `sr_gen` move and the man
page, both in 68156. **68288's patch, the test_166 fix the lab proved, is
byte-identical in every changed line**, so that result still stands as-is.

What has genuinely never run anywhere: the `sr_gen` reposition, and 68340's
added clears.

## What this lab tests

- **A.** `offsetof` against the **installed** header — `sr_class` at 204 (its
  pre-`sr_gen` offset) and `sr_gen` appended at 216.
- **B.** conf-sanity 165 + 166 on DNE — the scanner contract and fid2path.
- **C.** `sanity` ONLY=56, the whole `lfs find` suite, against the known
  baseline of 75 pass / 2 fail / 9 skip (`56Eaa` and `56xb` being the
  pre-existing pair). This also **cross-checks today's `test_56ob` finding on
  x86_64** without waiting for 68417's pending `custom` session.
- **D.** A walk crossing onto a tmpfs subtree inside Lustre, exercising
  68340's **original** `lmd_stx` fix: a non-Lustre file must not be reported by
  `-btime` from an inherited buffer.

## What it deliberately does NOT test, and why

**Round 11's own additions to 68340 — clearing `lmd_fid` and `lmd_lmmsize` —
are not observable from userspace, so no lab can prove them.** Checked rather
than assumed:

- `lmd_fid`'s only reader is `liblustreapi_scan.c:132`, on the scanner path —
  and that path **already clears `lmd_fid` itself** a few lines earlier
  (`liblustreapi_scan.c:~307`), with a comment giving the same reasoning. So
  the scanner never sees a stale FID with or without 68340's clear.
- `lmd_lmmsize` is read by `llapi_get_lum_file_fd()`
  (`liblustreapi_layout.c:6104`) only when the caller passes a `lum`, and **no
  in-tree caller does**.

Both are defensive hardening of a public API against out-of-tree consumers.
That is a code-review judgement, not a measurable one, and claiming a lab
"verified" them would be false.

**A correction this forced.** I had repeated the AI reviewer's claim that
"nothing in `lustre/utils` reads `lmd_fid`". That is true of 68340's own tree
on master, and false of the combined tree — our own 68094 adds the reader.
The distinction is what makes the clear worth having at all.
