# 68417 `cda04667`: `--since` printed a path twice — `LLAPI_SCAN_CL_F_ONCE`

The one open AI thread that was the user's to settle. Built 2026-09-06 as a
library flag rather than a private set in `lfs find`.

## The defect

`LLAPI_SCAN_CL_F_COALESCE` collapses an object's events only while the object
is held: `sc_min_age` is 600s and `sc_max_cached` is 100k, so an object
touched twice more than ten minutes apart — or evicted under pressure and
touched again — is delivered twice. `find_since_cand_cb()` then runs
`llapi_scan_fid()` twice on it and prints the path twice, where a walk prints
each path once. A file written once a day prints ~30 times under `--since 30d`.

## Where the fix went, and why

**In the library, behind `LLAPI_SCAN_CL_F_ONCE`,** not in a private FID set in
`find_since_cand_cb()`:

- **Testability.** From `lfs find` the only levers on re-delivery are
  `sc_min_age` and `sc_max_cached`, neither exposed, so a sanity case would
  have to create >100k objects between two touches to force an eviction. In
  the library `llapi_scan_changelog_test.c` sets `sc_max_cached = 1` and the
  case is deterministic and instant. That is test5.
- The memory bound belongs beside `sc_max_cached`, where the "window, not a
  database" comment already sets expectations.

**Memory was the objection; it is weaker than it looked.** `scan_dirmap`
already ships in this series as an open-addressed FID table holding *every
directory on the MDT* at 288 bytes an entry. This set is 16 bytes a slot over
the *changed* objects only, and it *saves* the duplicate `llapi_scan_fid()` —
an open plus a stat — which dwarfs the FID it stores.

Raising `sc_min_age` was rejected: `sc_max_cached` still evicts, so it reduces
duplicates without removing them.

`--changelog` does **not** set the flag. It reports the log, and a second burst
is a second thing that happened.

## What review of the diff caught, which the first version had wrong

The first version recorded an object as seen whenever the callback returned 0
— including when `find_since_cand_cb()` had *dropped* it. With the `--since`
window cut still in the callback, a burst from **before** the window would mark
the object delivered and suppress the burst **inside** it: a duplicate line
turned into a **missing** one, which is far worse than the defect being fixed.

Fixed by moving `lfs find`'s window cut into `sc_filter`
(`find_since_filter_cb()`), which runs before the `_ONCE` test, so a record
behind the window is never a delivery. The `--since-cookie` anchor moved there
too, and for a related reason: anchored on what the callback saw, it would lag
the log by whatever trailing run of suppressed records the scan ended on, and
the next run would report those objects again.

Every other reason the callback drops an object — gone, `find_decide()` says
no, outside the subtree — is a verdict on the object's *current* state, so a
later burst would answer the same. Those stay suppressed, which is the point.

## Placement in `scan_cl_deliver()`

After `sc_filter` (a consumer keeps its view of the whole stream), before the
resolve (what a duplicate would cost), and the FID is recorded only after the
callback took the record. A suppressed record still advances `sl_accepted`, or
`_CLEAR` would stall on a log whose tail is all repeats.

Only records that came out of the coalescing cache are keyed — the `keyed`
argument. A `CL_MARK` reaches `scan_cl_deliver()` through `scan_cl_event()`
with the mark's flags sitting in `cr_tfid`, and one of those is not a
duplicate of the next.

## Distributed across four commits

Scripted, per the method: `transform.py` applied at each rebase stop, validated
against the finished tree first (`applied=10 skipped=0 errors=0`, 0 lines vs
the verified tree, idempotent over three runs).

| Commit | Ticket / Gerrit | Share |
|---|---|---|
| `20956ec615` | LU-20649 / 68415 | the flag, the set, the man page, test5, the `-EINVAL` |
| `14cecf4547` | LU-20650 / 68417 | `find_since_filter_cb()` with the window cut; sets the flag |
| `0bc79ef960` | LU-20650 / 68418 | the flag becomes `--since`-only, `--changelog` keeps repeats |
| `ddb1f90f06` | LU-20650 / 68419 | the cookie anchor moves into the filter |

`725d409009` conflicted at its `edit` stop; resolved by taking the incoming
file whole and re-running the script, which is what makes the script the
definition of the change rather than the resolution.

Verified: tip identical to the tested tree; 20 commits before and after; 20
unique Change-Ids; all four build in isolation; checkpatch warnings unchanged
(0/1/1/1), the eight new checks all `== NULL` and `"..."DFID` house style that
matches the surrounding file.

**Not yet run on a lab** — the unit test and `--since` both need a live
filesystem with a changelog user. That is the outstanding gate.
