# Round 19: replying to the open AI review threads

## The count, and why the obvious count is wrong

`aireview` comments all carry `unresolved: true` on their own record, so
counting that flag reports **495 open** across the series and means nothing.
A thread's state is its **last** comment's flag. Computed properly:
**135 open AI threads**, 352 already answered.

`tests/gerrit-poll/` has the grouping code; the trap is recorded in
`lfu-daily-routine`.

## The split

| Group | Threads |
|---|---|
| On the newest AI-reviewed patchset per change | 49 |
| On much older patchsets (68415–68420 **PS1** alone is 57) | 86 |

The user scoped this round to the 49.

## Posted 2026-09-03 — 10 replies, each verified against `r16-work` first

| Change | PS | id | Verdict |
|---|---|---|---|
| 68094 | 15 | `f6fb41f2` | Done — page now says to copy `sr_lmmsize` bytes and decode the copy |
| 68094 | 15 | `a882d6a1` | Done — `llapi_scan_namespace (3)` is in `lustreapi.7` |
| 68094 | 15 | `3869d04f` | Done — "Whole seconds since the epoch" added |
| 68094 | 15 | `4186b3bf` | Half — dead `fp_min_depth` test removed; premise declined, `lfs find` does not go through this API |
| 68094 | 15 | `62b01bbb` | Declined — `HAS_STDATOMIC` is for C11 `<stdatomic.h>`, not the `__atomic_*` builtins |
| 68095 | 16 | `f60143a3` | Done — the message gained the printf/ENOTTY paragraph |
| 68095 | 16 | `38890fd7` | Done — now tests `!= -ENOTTY && != -ENODATA && != -ENOTSUP` |
| 68156 | 15 | `f9cd7c3b` | Done — ERRORS names the `ss_size` `-EINVAL` |
| 68156 | 15 | `b84ccc7a` | Done — `libscan_ldiskfs_a_CPPFLAGS` is empty |
| 68156 | 15 | `e21bfd46` | Done — `sb_worker_init` degrades like the `pthread_create` arm |

68095 is now fully answered. 68094 and 68156 have only their older-patchset
threads left.

## What the verification turned up — not everything was addressed

Round 18 fixed most of these, but **not all**, so a blanket `Done.` would have
been publicly wrong. Two found so far that are still live:

- **68156 `907b17a6`** — `EXT2_COMPR_FL` and `EXT2_NODUMP_FL` are still in the
  `so_flags` mask. The point stands: a namespace scan takes `sr_attr_flags`
  from what the MDT declares, which is only IMMUTABLE/APPEND/ENCRYPTED, so the
  same file answers `--attrs d` differently depending on which scanner ran.
  Needs a decision — mask it to what a namespace scan can produce, or state
  that a device scan is deliberately a superset.
- **68158 `f82298cf`** — the header still reads *"or -1 if there is none"* for
  both `@pathstartp` and `@pathendp`, and −1 in `@pathendp` means something
  else: no option followed the paths, so the range runs to `argc`.
  `1343a02c` is partly addressed — `@stopped` is now documented, but the
  `Return:` line still says "0 on success".

**These are round-20 work, not replies.** A thread whose finding is still open
should not get an answer until it has one.

## Remaining

39 of the 49 unverified. Each needs reading and checking against the tree
before it can be answered; the two above are why.
