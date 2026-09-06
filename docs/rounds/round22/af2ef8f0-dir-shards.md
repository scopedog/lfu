# 68288 `af2ef8f0`: a striped directory's shard became a path component

Verified in the tree, **reproduced and fixed on the lab**, on the same fixture.

## What it was

`scan_dirmap_cb()` inserted every directory that had a linkea name and parent.
A shard has both — its linkea is (name `<DFID>:<index>`, parent the master) —
and the pass asked for no LMV, so a shard went into the map like any
directory and its name reached the pathnames of everything under it.

Upstream drops that element: `mdt_path_current()` reads each linkea, calls
`mdt_is_dir_stripe()` (which tests `lmv_magic == LMV_MAGIC_STRIPE`) and on 1
sets `gf_fid` to the parent and continues **without packing a name**. We had
no equivalent, and pathname composition from the map has deliberately no
fallback to a lookup, so `--fid2path` reaches it too.

## Measured, before and after

Striped directory, eight files, filesystem taken down, scanned offline:

    lfind --device /tmp/lustre-mdt1 --paths -name 'f?'
    before:  /shardtest/[0x200000400:0x2:0x0]:0/f1     (and f3, f5, f7)
    after:   /shardtest/f1                             (and f3, f5, f7)

The "before" path is one no lookup answers, printed with a zero exit.

**A correction to the comment's repro line**: `lfs setdirstripe -c 1` does
*not* reproduce it. On this filesystem it makes a plain directory —
`lmv_stripe_count: 0`, no shard object at all. `-c 2` is what creates shards.

**And a nuance the comment did not mention**: on the *other* MDT the same
files are not misnamed but lost — `4 matching objects have no pathname and
were not printed`. Their shard is on MDT0001 while the master is on MDT0000,
so the walk cannot reach the root. That is the documented DNE limit, not this
defect, but it means one striped directory fails two different ways depending
on which target is scanned.

## The fix

- `LLAPI_SCAN_LMV_SHARD`, a new record bit beside `LLAPI_SCAN_LMV_FOREIGN`.
  It is set **without** `LLAPI_SCAN_LMV`: `scan_lmv_to_user()` has no
  `lmv_user_md` form for `LMV_MAGIC_STRIPE` and answers 0 to it, so the bit is
  the whole answer. Only a device scan sets it — a namespace walk never
  reaches a shard.
- The directory pass asks for `LLAPI_SCAN_LMV`, one `trusted.lmv` read per
  directory, which is what tells a shard from a directory.
- A shard is mapped with **no name**, and `scan_dirmap_path()` treats a
  nameless entry as a step to the parent rather than a component — the same
  shape as `mdt_path_current()`'s `continue`.

## Still open, and not this patch: the shard as an object of its own

`lfind --paths -type d` still prints the shard itself:

    /shardtest
    /shardtest/[0x200000400:0x2:0x0]:0

The map fixes *ancestors*; an object's own name still comes from its record.
A client mount shows a striped directory once, so this is a second difference
from `lfs find` and the same complaint — a path the filesystem does not have.

The principled answer is a **class**: `LLAPI_SCAN_CLS_*` already holds back
what is not namespace-visible (`_INTERNAL`, `_AGENT`, `_OST_OBJ`) unless
`LLAPI_SCAN_F_INTERNAL` is set, and a shard belongs in that family. That
changes what a scan delivers by default, so it wants its own patch, its own
justification and its own test rather than riding along here.

## Verification

Amended into 68288 (`2fdefcce9d` -> `a75a43fb2b`); `range-diff` shows that
commit alone changed. Tip identical to the tested tree, 20 commits, 20
Change-Ids, the commit and the tip build, checkpatch warnings unchanged. The
before/after arms ran against one fixture, built once, with only the userspace
swapped between them.
