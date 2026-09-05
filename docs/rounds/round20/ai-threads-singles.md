# Round 20 — the fourteen single threads

68094, 68156, 68158, 68159, 68160, 68163 and 68414.  Unlike the earlier
blocks these sit on PS9–PS15 against PS16–PS17, so a much higher
proportion of them are still live.

| change | thread | claim | state |
|---|---|---|---|
| 68094 | `ea53773b` | an `sp_size` off a field boundary tears `sp_filter` | **fixed now** |
| 68156 | `907b17a6` | `EXT2_COMPR_FL`/`EXT2_NODUMP_FL` cannot reach `sr_attr_flags` | fixed -- both flags are gone from the backend |
| 68156 | `ab78d3de` | the message never mentions `llapi_scan_stats`/`sp_stats` or `LLAPI_SCAN_F_INTERNAL` | **live -- message only** |
| 68158 | `f82298cf` | `-1` means something different in `@pathendp` | **fixed now** |
| 68158 | `1343a02c` | zero is not the success test; `@stopped` is | fixed, and tightened now |
| 68159 | `00a0464c` | the composite-EA swab is unbounded | fixed -- `find_lmm_fits()` bounds it first |
| 68159 | `e95d39cf` | a walk drops a `-btime` object silently | fixed |
| 68159 | `a32ed966` | a comment describing `scan_linkea_entry()` sits on another function | fixed -- both have their own |
| 68160 | `6fd1845c` | the `lfind` stanza sits inside the `lfs` one | **fixed now** |
| 68160 | `3af3a80a` | the message says nothing about the conf-sanity hunk; was the guard dropped? | guard is there (`do_facet mds1 "test -x $scanner"`); **message live** |
| 68163 | `16169694` | a missing device is reported as a missing ZFS backend | fixed -- a leading `/` routes to ldiskfs |
| 68414 | ×3 | changelog mask composition | **not looked at yet -- different worktree** |

## `ea53773b` — the one that mattered

`LLAPI_SCAN_PARAM_MIN_SIZE` is 24 and `sizeof(struct llapi_scan_param)`
is 64, and the check was only a range:

    if (sp->sp_size < LLAPI_SCAN_PARAM_MIN_SIZE || sp->sp_size > sizeof(spl))
            return -EINVAL;
    memcpy(&spl, sp, sp->sp_size);

Nothing required the size to land on a field boundary.  `sp_filter` sits
at [24, 32), so an `sp_size` of 25..31 copies **part of a function
pointer** and zero-fills the rest, leaving `spl.sp_filter` non-NULL and
not a function -- and the scan calls through it.  `sp_stats`,
`sp_search` and `sp_fsname` are pointers in the same position further up,
dereferenced rather than called.

A caller's size field is always the `sizeof()` of the struct its own
header declared, so it always ends on a boundary; every version's
`sizeof` is a multiple of the struct's alignment.  That is the test:

    static inline bool scan_size_ok(__u32 size, __u32 min, size_t max,
                                    size_t align)
    {
            return size >= min && size <= max && size % align == 0;
    }

The AI raised it on 68094, but the same range check had been copied to
**five** places, and the changelog parameter has five pointer fields of
its own.  All five now go through the helper:

    liblustreapi_scan.c        x2  (llapi_scan_namespace, llapi_scan_fid)
    liblustreapi_scan_device.c x1
    liblustreapi_pfind.c       x1
    liblustreapi_scan_changelog.c x1  (sc_size)

Each fix landed in the commit that introduced its own site -- 68094,
68416, 68156, 68159 and 68415 -- so no commit depends on a later one.

### Proved, not argued

Linked a program against the built library and swept every size:

    sizeof(struct llapi_scan_param) = 64, offsetof(sp_filter) = 24
      size 24 ACCEPTED   size 32 ACCEPTED   size 40 ACCEPTED
      size 48 ACCEPTED   size 56 ACCEPTED   size 64 ACCEPTED
    (every size not listed above was refused with -EINVAL)

Exactly the six field boundaries, and nothing else -- 25..31 included.

Every internal caller passes `sizeof`, so nothing in the tree changes
behaviour.  The three sizes the unit tests assert on are all still
answered the same way: `MIN_SIZE` (24) accepted, `sizeof + 8` refused,
`sc_size = 4` refused.

## Lab

`~/lustre-r18`, ldiskfs, MDSCOUNT=2 OSTCOUNT=2, with all five sites
patched and userspace rebuilt:

    llapi_scan_test -d /mnt/lustre     11 of 11 pass
      including test6 "bad arguments are refused, not crashed on"
      and     test5 "sp_filter rejects an object before its attributes
                     are read" -- the field the tear corrupts

    sanity 56El, 160aa, 160ab, 160ac, 160ad   all PASS

## Still open

- **68414's three threads** (`766a671a` missing `Fixes:`, `724d521c`
  disjoint masks composing to zero and reading as "no filter",
  `4136f6d5` `changelog_chmask` restoring only `$SINGLEMDS`).  68414
  lives in the `lustre-lu20648` worktree on `r16-pair`, not in
  `r16-work`, so it needs its own pass.  `724d521c` looks like a real
  wrong answer of the same shape 68414 is already fixing.
- **Two commit-message threads** (`ab78d3de`, `3af3a80a`).  Both are
  substantive rather than cosmetic -- new public API absent from the
  message, and a third of a diff unexplained -- so they are worth a
  message rewrite rather than a decline, batched with 68415's
  `b2878aee`.
- **lreview**, which waits for the backlog.

18 changes, 18 Change-Ids.  `lfs`, `lfind` and `liblustreapi` build
under `-Werror`.  checkpatch: 0 errors on all seven touched commits;
68158's 14 warnings are all in the upstream code it moves, none in the
header this round edited.
