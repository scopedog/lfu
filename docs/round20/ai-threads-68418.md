# Round 20 — 68418's nine AI threads

All nine sit on PS1; the change is at PS8.  Seven were already fixed in a
later patchset -- and they are the serious ones, which is worth saying
plainly, because reading the PS1 comments cold they look alarming.

| thread | claim | state |
|---|---|---|
| `3a23062a` | `fnmatch(pattern, NULL)` segfaults on a nameless record | fixed -- the `sr_name != NULL ? rec : &named` fallback, and a nameless record with `-name` is counted undecided |
| `6727fa82` | `sc_want = 0` means "nothing", so `-uid` matches everything | fixed -- the mask names its fields explicitly (`FID\|EVENT\|EVENT_SRC\|JOBID\|PARENT\|EVENT_UID\|TYPE`) |
| `155cd1ef` | the subtree is never applied under `--resolve` | fixed -- `find_since_pick()` runs `find_since_under()` on the resolved path, and `find_changelog_rec_cb()` goes through it |
| `71772f48` | the merged record drops `sr_path`/`sr_parent_fd`/`sr_fd` | fixed -- `find_cl_merge_cb()` starts from the live record (`rec = *live`), so it keeps all three |
| `a1df078d` | `--xattr` reaches `llistxattr(NULL)`; `-perm`/`-links`/`--attrs` compare against zeros | fixed -- all four refused by name in `find_changelog_supported()` |
| `0590b53b` | `sr_parent_fid` not copied while its bit is OR'd in | fixed -- copied under `LLAPI_SCAN_PARENT`, with the reason |
| `0d7e01a3` | bare `--resolve` accepted and silently dropped | fixed -- refused in the parser, which `lfind(1)` shares |

## `646d2c0a` -- fixed now: a public struct grew a byte it did not need

`fp_resolve` was added as `unsigned char` at the end of `struct
find_param`, while the struct carries `fp_unused_bit2..4` under a comment
saying what they are for: *"once used, we must add a separate flag field
at the end of this struct"*.  Our own series already follows that rule --
`fp_paths` took bit 1 -- so `fp_resolve` taking a new byte was the
inconsistency.

Moved onto `fp_unused_bit2`.  This **shrinks** the public struct rather
than growing it, which is the better direction for a field landing in the
same release, and it keeps the reserved bits meaning what they say.

## `c81f620e` -- half was fixed, half is fixed now

The man-page and usage-string half is done: `lfs-find.1` names
`--changelog` 21 times and `--resolve` 8, and `lfs.c`'s usage carries
`[--changelog MDT|all]` and `[--resolve]`.

The placement half was still live.  The long-option table is name-ordered
within each short-option group, and `changelog` sat after the
commented-out `q`/`r`/`R` getstripe entries, between `projid` and
`resolve` -- where a paste lands, not where a `c` option belongs.  Moved
up next to `crtime`, before `comp-count`.  `resolve` and `since` were
already in their right places.

## Lab

`~/lustre-r18`, ldiskfs, MDSCOUNT=2, OSTCOUNT=2, with the `fp_resolve`
bitfield applied and userspace rebuilt:

| test | result |
|---|---|
| `sanity 160aa` `--since is a subset of the same find` | PASS |
| `sanity 160ab` `--changelog refuses what a record cannot answer` | PASS |
| `sanity 160ac` `--since-cookie resumes where it stopped` | PASS |
| `sanity 160ad` `--since finds a hardlink under either name` | PASS |

And by hand, because `fp_resolve` is the field whose storage changed --
note `changelog_mask` is `MARK` by default, so an empty answer means an
empty log and not a broken option, which cost me one confused reading:

    lfs find /mnt/lustre --changelog all --resolve   -> d_res, a.log, b.txt
    lfs find /mnt/lustre --changelog all -name '*.log' -> a.log only
    lfs find /mnt/lustre/d_res --changelog all --resolve -> confined to d_res
    lfs find /mnt/lustre --resolve                   -> refused, as designed

The `-name` line is the one that matters twice over: it is `3a23062a`'s
segfault case, and it filters correctly rather than matching everything.

`checkpatch`: 68418 clean (0/0).  68417 shows the two standing false
positives only (MAINTAINERS for a new man page, `time_t` "misspelled").
`lfs` and `liblustreapi` build under `-Werror` at the tip.  18 changes,
18 Change-Ids.
