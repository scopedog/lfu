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

## Posted 2026-09-03 — 47 replies, each verified against `r16-work` first

Every one of the 49 in scope was read and checked against the tree before it
got an answer. **42 were already addressed by round 18** and got `Done.`; one
got a reason; **seven are still live and were left open**.

| Change | PS | Posted | Left open |
|---|---|---|---|
| 68094 | 15 | 5 | — |
| 68095 | 16 | 2 | — |
| 68156 | 15 | 3 | `907b17a6` |
| 68158 | 9 | — | `f82298cf`, `1343a02c` |
| 68159 | 15 | 3 | — |
| 68160 | 10 | 3 | `3af3a80a`, `6fd1845c` |
| 68163 | 14 | — | `16169694` |
| 68231 | 2 | 1 | — |
| 68288 | 9 | 3 | `222a9f0d` |
| 68415 | 7 | 9 | — |
| 68416 | 7 | 2 | — |
| 68417 | 7 | 3 | — |
| 68418 | 7 | 7 | — |
| 68419 | 7 | 3 | — |
| 68420 | 7 | 3 | — |

Three replies carried a reason rather than `Done.`:

- **68094 `4186b3bf`** — half: the dead `fp_min_depth` test is gone, the
  premise declined, `lfs find` does not go through this API.
- **68094 `62b01bbb`** — declined: `HAS_STDATOMIC` is for C11
  `<stdatomic.h>`, not the `__atomic_*` builtins.
- **68288 `db3e58ad`** — the premise is gone. It asked us to refuse
  `--fid2path` on ZFS because `lfind(8)` said it was impossible; round 19
  deleted that stale paragraph, and `conf-sanity` test_167 passes on
  `conf-sanity4@zfs`.

## The seven left open, and why

A thread whose finding is still live should not get an answer until it has
one. These are round-20 work:

| Where | What |
|---|---|
| 68156 `907b17a6` | `EXT2_COMPR_FL`/`EXT2_NODUMP_FL` still in the `so_flags` mask, so `--attrs d` answers differently depending on which scanner ran |
| 68158 `f82298cf` | header still says *"or -1 if there is none"* for `@pathendp`, where −1 means the range runs to `argc` |
| 68158 `1343a02c` | `@stopped` is documented now, but `Return:` still says "0 on success" |
| 68160 `3af3a80a` | the message still says nothing about the `conf-sanity.sh` hunk, a third of the diff |
| 68160 `6fd1845c` | the `lfind` block still sits between `lfs_SOURCES` and `lfs_CFLAGS` |
| 68163 `16169694` | a `stat()` failure still routes to the ZFS backend, so a mistyped device on an ldiskfs-only build reports `-ENOTSUP` and names ZFS |
| 68288 `222a9f0d` | still no public way for an out-of-tree caller to match a mount to a scanned target |

## Remaining beyond this round

**88 open threads**, of which 81 sit on much older patchsets (68415–68420
**PS1** alone is 57). Those want the same treatment and a comment-and-verdict
file of their own.
