# Round 20 — 68417's eleven AI threads

All eleven sit on PS1; the change is at PS8.  Six were already fixed in a
later patchset, two are fixed now, three are left with reasons.

| thread | claim | state |
|---|---|---|
| `06ee0f50` | `--since` in neither `lfs-find.1` nor the usage string | fixed -- the man page names it 25 times, the usage string carries `--since` and `--since-cookie` |
| `fc37a600` | `find_prefilter()` never runs, so `-name` answers a superset | fixed -- `find_since_rec_cb()` calls it, and says why |
| `99e9288e` | `gather_all` never set, so `-printf` prints partial values | fixed -- set on both `--since` paths from `fp_format_printf_str` |
| `30d69a23` | the block split `llapi_find_device()`'s kernel-doc from its definition | fixed -- the doc sits on its function again |
| `eaf5143c` | "a strict subset, narrowed and never different" is false for `-name` | fixed -- with `fc37a600` it is true again |
| `efad0e67` | a callback error reported as "cannot read the changelog" | fixed -- the callback's own rc is told apart |
| `eb6c443c` | `fss_root_depth` is never written or read | **fixed now** |
| `b0fd2248` | "coalescing has already reduced an object to its latest event" | **fixed now** |
| `122b863e` | probes 64 indices with `llapi_search_tgt()` per path argument | left -- see below |
| `dbb03e33` | "or name one MDT" names an option that does not exist | left -- 68418 adds it |
| `cda04667` | an object touched twice can be printed twice | **live, and a design call** |

## `eb6c443c` -- a dead field

`fss_root_depth` was declared in `struct find_since_state` and never
written or read; `find_since_under()` recomputes the depth from the
pathname on every call.  Removed.  68418 adds its `--changelog` fields
immediately after it, which is why removing it conflicts there; the
conflict is the deletion against those additions and nothing else.

## `b0fd2248` -- the comment claimed something untrue

Over the time-anchor test in `find_since_cand_cb()`:

> Coalescing has already reduced an object to its latest event, so an
> object whose latest event is older than the window did not change in it.

That holds only inside `sc_min_age`.  `scan_cl_flush()` delivers and frees
an object as soon as the stream clock has moved `sc_min_age` (600s by
default) past its last event, so over a window longer than that an object
arrives **once per burst**, not once.

The **test is still right** -- each arrival carries its own event time and
this drops the ones behind the window, so an object that changed inside
the window still arrives with an event inside it.  It was the reasoning
that was wrong, not the code, so the comment is what changed.

## `cda04667` -- real, and it needs your call

The same fact `b0fd2248` names has a consequence the comment was hiding.
An object touched twice more than `sc_min_age` apart **inside** the window
is delivered twice, so:

    lfs find /mnt/lustre --since 7d

runs `llapi_scan_fid()` twice on it and **prints the path twice**, where a
plain `lfs find` prints each path once.  There is no dedup on the `--since`
path -- I checked `find_since_cand_cb()` end to end.

I have not fixed it because both available fixes cost memory proportional
to the answer:

- a **seen-FID set** in `find_since_cand_cb()` -- exact, and it also saves
  the duplicate `llapi_scan_fid()` lookup, which is an open and a stat and
  far more expensive than the 16 bytes.  But `--since 30d` on a busy
  filesystem could hold tens of millions of FIDs;
- **raising `sc_min_age`** so the whole log coalesces -- no new structure,
  but `sc_max_cached` still evicts, so it reduces duplicates without
  removing them.  Not a fix, a mitigation.

A plain walk needs no such set because the tree visits each object once;
a log does not have that property.  Which way to go is a memory-versus-
exactness call on a public option's contract, so it is yours.

## `122b863e` and `dbb03e33` -- left, with reasons

`122b863e`: the probe loop is `llapi_search_tgt()` over every index up to
`ltd_tgts_size`, and the AI is right that `llapi_get_target_uuids()` would
give the live indices in one ioctl.  But it runs **once per path argument
at startup**, not per object, so it is ~64 small reads against a scan of
the whole changelog.  Worth doing on the next touch of that function, not
worth a patchset.

`dbb03e33`: "Give a time (--since 2h, --since @<ts>) or name one MDT" is
accurate **once 68418 lands** -- `--changelog <mdt>` is the option it
promises, and the two land together.  On 68417 alone it points at nothing,
which is what the AI saw.  Left as it is because the series is the unit.

`checkpatch`: 0 errors, 0 warnings.  `lfs` and `liblustreapi` build under
`-Werror`.  18 changes, 18 Change-Ids, after the rebase.
