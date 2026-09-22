# The 09-22 AI round on batch 1 and its neighbours — 24 comments

The reviewer ran overnight on all eight pushed changes: 68094 (4), 68095 (2),
68156 (5), 68157 (2), 68158 (1), 68159 (2), 68160 (7), 68163 (1). One
defect, the rest minors and style. **All 24 are answered — 22 by a fix, one
by a reply owed, one recorded as belonging to its own patch.**

Each fix lands in the commit the finding was raised against, not at the top
of the stack: `genfix.py` grew a `FILE_SINCE` map for the files whose fixes
are all one commit's, and `SINCE_MARKERS` for the two files that carry
fixes for several.

## The defect: an integer wrap in the %Lo bound (68159)

`lmv_user_md_size()` returns `unsigned int` and adds
`count * sizeof(struct lmv_user_mds_data)`, and the count comes straight off
the device. Proved before fixing, with the real header:

| count | size | guard |
|---|---|---|
| 1, 2, 256, 2000, 2001 | 72 … 48072 | break, as intended |
| **0x20000000** and its multiples | **48** | **falls through** |

`48 < 48` is false, `str_cnt` becomes the count off the device, and the loop
walks `objects[i]` out of an `fp_lmv_md` sized for 256 stripes until the
output buffer fills — about 500 entries, so roughly 6 KB past the end.

Fixed at both ends: the count is refused above `LMV_MAX_STRIPE_COUNT` where
it is read in `scan_lmv_to_user()` (c02), and the bound is measured from the
record's bytes rather than multiplied back (c05). Proved against the
unfixed guard — identical for every legitimate count, rejecting where the
old one accepted.

## Fixed

- **68094** the `LLAPI_SCAN_LAYOUT` bit is a *default* layout for a
  directory, and may be the filesystem root's; `lstddef.h` no longer reaches
  27 translation units for one `ARRAY_SIZE`; a test for the `lfsp_flags`
  rejection; RETURN VALUES now says objects may be omitted without
  `LLAPI_SCAN_F_STOP_ON_ERROR`.
- **68095** one `lmv_is_foreign()` test at the top of the directory branch
  instead of on `%Li` alone: a foreign LMV is a different structure at the
  same address, so `%Lc` printed its value's length as a stripe count and
  `%Lp` part of its payload as a pool name. The `find_foreign_accepts()`
  comment now says the shortcut skips the other predicates too.
- **68156** four body claims that described an earlier revision of the patch
  rather than the tree; the `ss_size` ERRORS entry; `ss_size` rounded down to
  a whole counter at both write-back sites, so a size landing inside one no
  longer leaves the caller half a number; `LLAPI_SCAN_HSM` added to the prose
  list.
- **68157** the two edits missing from the message's audit list; the
  `fc_path` comment now names the steps that are guarded instead of claiming
  they all are.
- **68158** the phantom `"param." becomes "param->"` bullet dropped.
- **68159** the wrap above, and `%Lc`/`%Lp` covered by the same foreign test.
- **68160** positive assertions in conf-sanity's `--local` checks, so an
  empty `$scan_err` can no longer pass both greps while checking nothing;
  the doubled program name in `llapi_error()`; the loop-invariant
  `pathstart != -1`; `llapi_name_verify()` reused, which also tells too-long
  from a bad character (and conf-sanity's grep moved with it); a note that
  the three `argv` pointers are borrowed, so nobody teaches
  `lfs_find_parse_fini()` to free them.
- **68163** `.` and `..` are directories, so `lfs find --device ..` reached
  the kstat probe and was told to export a pool that was never named. A pool
  name has to start with an alphanumeric.

## Not fixed

- **68160, Andreas's `--label`/libblkid suggestion**, raised on PS20 and
  never answered. It wants a new libblkid dependency, which nothing in the
  tree links today, so deferring is reasonable — but the thread is owed a
  reply saying so rather than being left open.
- **68095's `goto print` shortcut** skipping the remaining predicates is
  upstream's own and belongs in its own patch; the comment now says so.

## Artem Blagodarenko, the same day

Read 68094 and 68156 and was positive: *"I have read this code. I think it
is correct and buituful. I have placed some comments, but do not expect the
patch will be fixed. Just for referance in next patches."* So his four are
carry-forward, not a re-spin: print `struct llapi_scan_param` in
llapi_scan_namespace.3 the way llapi_ladvise.3 does; a test assertion that
assumes a gathered count of 2; one "overkill but not a problem". His
68156 question about an OST's internal namespace he answered himself --
`fid_is_namespace_visible()` excludes it.
