# `llapi_scan_fid()` — filling a record for one FID

**Date:** 2026-08-26 · **Status:** design, **v0.1**, no code yet ·
**Parent architecture:** [`architecture.md`](architecture.md) ·
**Blocks:** `lfs find --since` and `lfs find --changelog --resolve`, steps 4–5
of [`design-changelog-scanner.md`](design-changelog-scanner.md).

Code references are to `../lustre-lu20649` @ `38e691a616` (LU-20649 on top of
the round-10 stack), and are **[verified]** where the line was read.

---

## 0. The recommendation, in one page

**Add a fourth entry point beside the three that exist, not a mode on one of
them, and make it resolve through `fid2path` and gather at the resulting path
rather than gathering from a descriptor opened by FID.**

```c
int llapi_scan_fid(int mnt_fd, const struct lu_fid *fid,
		   const struct llapi_scan_param *sp,
		   llapi_scan_cb_t cb, void *data);
```

Four sources, one record, one vocabulary:

| | identity | universe | ends? |
|---|---|---|---|
| `llapi_scan_namespace()` | a path | what exists, below it | when the walk finishes |
| `llapi_scan_device()` | a device | what exists, on that target | when the device is exhausted |
| `llapi_scan_changelog()` | an MDT | what *happened* | `_FOLLOW` never ends |
| **`llapi_scan_fid()`** | **one FID** | **one object, as it is now** | **immediately** |

**Why it has to exist:** the changelog module resolves privately today, and it
resolves with `fstat` alone. `scan_cl_resolve()` **[verified,
`liblustreapi_scan_changelog.c:182-244`]** fills mode, nlink, uid/gid, the
three timestamps, size and blocks — and nothing else. It does not fill the
layout, the HSM state, the project id, the MDT index or the dirstripe. So a
changelog-sourced record can answer `-size` and `-mtime` but not
`-stripe-count`, `--hsm-state` or `-projid`, and `lfs find --since
-stripe-count 4` would answer differently from a plain `lfs find` on the same
filesystem. That is a defect, not a provenance difference: `--since` promises
*as it is now*, verified through the mount, and a promise that covers six
predicates out of eighty is not the promise.

---

## 1. Why not a mode on `llapi_scan_namespace()`

Asked directly on 2026-08-26. The answer is no, on three grounds.

**The shared parameter block already shows the cost.** `struct
llapi_scan_param` is shared between the walk and the device scan today, and it
already carries two fields dead for one of them **[verified,
`lustreapi.h:791-808`]**:

```c
	/* filled by llapi_scan_device() when the scan ends; the
	 * namespace scanner does not use it.  NULL: not wanted
	 */
	struct llapi_scan_stats	*sp_stats;
	/* ... Today that is the ZFS backend ... */
	const char		*sp_search;
```

Two is a smell. Folding the changelog in would add `sc_mdtname`, `sc_user`,
`sc_startrec`, `sc_endrec`, `sc_type_mask`, `sc_min_age`, `sc_max_cached` and
`sc_mnt`, plus four flags — every one meaningless to a walk, in a struct where
nothing tells the reader which half applies.

**A walk cannot skip to the changed objects.** §13.1 of the changelog design
settled this for the CLI and it holds for the API: a `--since` implemented
inside the walk would read the log *and then walk everything anyway*. The
accelerator would accelerate nothing.

**What deserves to be shared already is.** `struct llapi_scan_rec` and
`llapi_scan_cb_t` are the common surface; the sources differ in identity, in
universe and in whether they terminate. Making one source a mode of another
breaks the symmetry and invites the question the design has no answer to: why
does the changelog live inside the namespace walk when the device scanner does
not?

---

## 2. `fid2path` and gather, not open-by-FID and gather

This is the decision worth arguing, because the cheaper-looking route is the
wrong one.

`scan_rec_gather()` is **path-oriented throughout** **[verified,
`liblustreapi_scan.c:287-403`]**: `get_lmd_info_fd(path, p, d, ...)` wants a
parent descriptor and a name or a directory descriptor; `get_projid(path, ...)`
opens by path; the HSM branch does `open(path, O_RDONLY | O_NONBLOCK)`; the
MDT-index branch does `open(path, O_RDONLY)` for a regular file; the LMV branch
calls `llapi_scan_get_lmv(path, dp, param)`.

So there are two routes.

**Route A — resolve, then gather at the path.** `llapi_fid2path_at()` for the
pathname, then `scan_rec_gather()` exactly as the walk calls it.

**Route B — open by FID, gather from the descriptor.** `llapi_open_by_fid_at()`
and then a descriptor-shaped variant of the gather.

**Route A wins, and not narrowly.**

1. **Route B needs a second copy of the gather.** Every branch quoted above
   would need an fd-shaped twin. A second copy of that knowledge is precisely
   what the LU-20611 rewrite existed to remove; adding one back to serve a
   fourth entry point would undo the argument the series is being reviewed on.
2. **`--since` needs the pathname anyway.** It prints pathnames, and it
   enforces a subtree restriction by prefix-matching the resolved pathname
   (§13.1, rule 2). `fid2path` is not an extra cost on the `--since` path; it
   is required work that Route B would have to do as well.
3. **An object that no longer resolves is the correct answer.** `--since`
   answers *as it is now*: an object unlinked since the event cannot be
   verified and drops out. Route A gets that from `fid2path` returning
   `-ENOENT`, with no special case.

**What Route A costs, stated plainly.** One `fid2path` RPC per candidate, and
`llapi_fid2path_at()` needs `CAP_DAC_READ_SEARCH` unless `llite.*.user_fid2path`
is set — the same constraint `llapi_scan_rec_path()` already documents
**[verified, `liblustreapi_scan.c:600-618`]**. A caller without that
capability gets `-EPERM`, and `--since` must say so rather than silently
returning fewer objects.

---

## 3. The signature, field by field

```c
int llapi_scan_fid(int mnt_fd, const struct lu_fid *fid,
		   const struct llapi_scan_param *sp,
		   llapi_scan_cb_t cb, void *data);
```

**`mnt_fd`, not a path.** `llapi_scan_rec_path()` already takes `int mnt_fd`
**[verified]**, and `--since` calls this once per candidate in a loop of
thousands. Opening the mount per FID would be absurd; the caller opens it once.

**A callback, not a returned record.** `sr_path`, `sr_name`, `sr_lmm` and
`sr_lmv` point into the scanner's buffers, so the record is valid for the
duration of the call — the same contract the other three state. Returning a
record would make lifetime the caller's problem for the first time in the
family.

**`sp` is the existing block, and only `sp_want` and `sp_filter` mean
anything.** `sp_max_depth`, `sp_thread_count`, `sp_stats` and `sp_search`
describe a traversal there is none of. This is the same wart §1 refuses to
multiply, so: **document them as ignored, and refuse a non-zero
`sp_thread_count` rather than ignoring it silently**, because a caller setting
it has misunderstood what the call does.

**Return:** 0 with the callback called once; `-ENOENT` if the FID no longer
resolves; `-EPERM` if the caller may not resolve FIDs; the callback's own
value unchanged if it returns non-zero, as the other three do.

---

## 4. It fills; the caller merges

`llapi_scan_fid()` fills a fresh record from the live object. It must not be
handed a record that already carries event-recorded fields, because the rule
that makes `--changelog` mean anything is that **resolution fills what the
stream lacks and never restates what it has** (§13.1).

So the two consumers compose it differently:

| | what it does with the filled record |
|---|---|
| `lfs find --since` | **takes it whole.** The answer is *as it is now*; the event supplied only the candidate |
| `lfs find --changelog --resolve` | **merges only the absent fields**, exactly as `scan_cl_resolve()` does today with `if (!(rec->sr_valid & LLAPI_SCAN_UID))` |

Keeping the merge in the caller is what keeps the two flags apart. A
`llapi_scan_fid()` that took a partly-filled record and "topped it up" would
put the as-recorded rule inside a call that has no idea which source it is
serving.

---

## 5. What `--since` then is

No new predicates, no fourth copy of the vocabulary:

```
	llapi_scan_changelog()  in object mode   -> candidate FIDs
	  llapi_scan_fid()      per candidate    -> a record, filled as the walk fills it
	    find_decide()                        -> the existing predicates
```

Which is the composition §13.1 described before any of it existed. The three
pieces are already there apart from the middle one.

---

## 6. Open

- **Does `--since` want a batch form?** One `fid2path` and one gather per
  candidate is two RPCs per object where a walk pays roughly one. For a window
  of a few thousand objects that is not worth an API; for a day's changelog on
  a busy filesystem it might be. Measure before adding one.
- **`sr_parent_fd` is `-1` here**, as it is above one thread in the walk
  (round 10's man-page fix). Worth stating in the man page for the same reason.
- **Version.** `llapi_scan_fid()` is new public API and needs the same
  `sp_size`-style discipline the others have; it takes the existing
  `llapi_scan_param`, so nothing new is versioned.
