# lreview on 68415 — four findings, three fixed, one held

**4 findings, severity low, 17m28s, 10.4M tokens, $9.13.**

| id | finding | state |
|---|---|---|
| `(3)` symlink excluded from the size fetch | **fixed** — a real cross-scanner inconsistency |
| `(2)` the man page says `sr_name` is the latest event's | **fixed** — it is the latest that *carried* one |
| `(1)` 325 lines of test arrive unexplained by the message | **fixed** |
| `(4)` `llapi_scan_changelog(mdtname, sc, cb, data)` to match its siblings | **held** — API shape, see below |

## `(3)` — the one that mattered

`scan_cl_resolve()` wrapped its size fetch in `if (!S_ISLNK(st.st_mode))`,
so a symlink came back with **no size and no valid bit**, while both
sibling scanners answer for one:

- `liblustreapi_scan_device.c` takes its `!S_ISREG(so_mode)` branch and
  sets `LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS`;
- `liblustreapi_scan.c` sets them from the statx mask with no type test.

So `-size` was undecided from a changelog and decided from the other two
**for the same object** — the "one field means one thing whichever
scanner filled it" contract this series defends elsewhere (it is the
stated reason for the LMV-magic fix and the `sr_attr_flags` narrowing in
68156).

The guard also contradicted the comment directly above it, which says
*"Nothing but a regular file has stripes, so for the rest the MDT's
answer is the answer and the strict bits are right"* — which covers
`S_IFLNK` as much as `S_IFDIR`.  Removed; the inner `!S_ISREG` test
already gives a symlink the strict bits, correctly, since it has no
stripes.

### Proved with a control, and the first attempt proved nothing

`lfs find --changelog --resolve -type l -printf '%s'` printed **32 both
with and without the fix**.  That is not the fix failing — it is the
wrong probe: `find_cl_merge_cb()` starts from `llapi_scan_fid()`'s record
and overlays the event's fields, so `lfs find` gets the size from the
lookup, not from `scan_cl_resolve()`.  The code changed here serves
**direct API consumers** of `llapi_scan_changelog()`.

A small program calling the API with `LLAPI_SCAN_CL_F_RESOLVE`, run
against each library in turn:

| library | symlink record |
|---|---|
| with the `S_ISLNK` guard | `SIZE bit=**ABSENT**  sr_size_bytes=0` |
| fixed | `SIZE bit=SET  sr_size_bytes=32` |

`stat` says 32 for that symlink, so the fixed answer is the right one.
Had I stopped at the `lfs find` probe I would have recorded "no
observable difference" and either reverted a correct fix or shipped it
unverified.

## `(2)` — the man page said the opposite of what the code does

> The record carries the object's **latest** event: its
> `sr_event_index`, `sr_event_time`, `sr_event_type` **and `sr_name`**
> are that event's and not an earlier one's.

`sr_name` is not.  `scan_cl_absorb()` replaces `co_name` only when
`cr_namelen != 0`, and `mdd_changelog_data_store_by_fid()` writes none
for `CL_CLOSE`, `CL_TRUNC`, `CL_SETATTR` and their kind — so
create+write+close coalesces to one record whose `sr_event_type` is
`CL_CLOSE` while its `sr_name` is the one `CL_CREATE` recorded.

**Keeping the older name is right** — taking the latest event's would
leave most coalesced records with no name at all — so the code stands and
the sentence changed.  The page now separates the fields an event always
carries from those it does not, and names the other five that follow the
same rule: `sr_parent_fid`, `sr_jobid`, `sr_src_fid`,
`sr_src_parent_fid`, `sr_src_name`, `sr_event_uid`.  Renders clean under
`groff -ww`; `checkpatch-man` reports only the pre-existing 82-column
`.TH` line.

## `(1)` — and the coverage gap behind it

The message never mentioned `llapi_scan_changelog_test.c` or the two
`Makefile.am` hunks that build it.  It now says what the five cases
cover and how it is invoked.

The reviewer's larger point stands and is **recorded, not fixed**:
nothing in `lustre/tests` drives that binary, where both sibling scanners
landed their suite case in the same patch (`sanity 157c` drives
`llapi_scan_test`, `conf-sanity 165` drives `llapi_scan_device_test`).
The case needs a changelog registered and cleared around it and a skip
where the MDT records nothing.  Named in the message as owed rather than
grown here, because it is a test patch of its own.

## `(4)` — held

Making `mdtname` the first argument, as `llapi_scan_namespace()` and
`llapi_scan_device()` take their target, is a public signature change.
It lands in the same area adilger is questioning (parameter struct,
`sp_size` semantics, statx reuse), so it waits for those answers rather
than being decided twice.

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2: **56El, 160aa, 160ab, 160ac, 160ad pass;
`llapi_scan_test` 11 of 11.**  checkpatch 0 errors.  18 changes, 18
Change-Ids.
