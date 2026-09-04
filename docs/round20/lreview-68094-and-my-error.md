# lreview on 68094 — four findings, and a fix of mine that should not have existed

`lreview` on 68094: **4 findings, severity low, 16m01s, 9.3M tokens,
$8.42.**  Three of the four are about a change *I* made earlier in this
session, and they are right.

## What I got wrong

The Gerrit AI thread `ea53773b` said an `sp_size` off a field boundary
tears `sp_filter`, quoting:

    memcpy(&spl, sp, sp->sp_size);   /* sp_size = 28 */
    st.ss_filter = spl.sp_filter;    /* non-NULL, and not a function */

I read the range check two lines above that call, agreed, and added a
`scan_size_ok()` refusing any size not a multiple of the struct's
alignment -- across five sites.  **I never read the memcpy.**

It already said:

    memcpy(&spl, sp, scan_param_whole(sp->sp_size));

`scan_param_whole()` rounds the size down to the last whole field, so
`sp_size = 28` copies 24 bytes and `sp_filter` is wholly zero.  **The
tear could not happen.**  An earlier round-20 session had fixed it; the
AI comment was written against PS10 and quoted the old code, and I took
the code from the comment instead of from the tree.

This is the exact failure [[lfu-daily-routine]] step 2 exists to
prevent, and which my own notes record from 2026-08-20: *"acting on one
comment's text re-broke a correction."*

My behavioural "proof" -- only 24/32/40/48/56/64 accepted -- demonstrated
that my new code did what I wrote, not that it fixed anything.  A
before/after against the unfixed library would have shown no difference,
and I did not run one.

### What the reviewer caught

| # | finding | verdict |
|---|---|---|
| 1 | the commit message paragraph no longer describes the code | real -- my change made the message stale |
| 2 | the comments name `sp_stats`, `sp_search`, `sp_fsname`, `llapi_scan_changelog()`, `LLAPI_SCAN_CL_PARAM_MIN_SIZE`, none of which exist at 68094 | real -- partly mine, partly pre-existing |
| 3 | `scan_size_ok()` and `scan_param_whole()` give contradictory reasons for the same defence, and mine makes the other unreachable | real, and the decisive one |
| 4 | a comment block sits above the wrong function | style |

Finding 3 is the one that settles it: with `scan_size_ok()` in front,
`scan_param_whole()` could never round anything, because every size it
would have rounded was already refused.  Two mechanisms for one
hazard, disagreeing about whether to round or refuse.

## Reverted

`scan_size_ok()` removed, and all four `sp_size` sites restored.
`liblustreapi_scan.c` and `liblustreapi_scan_device.c` are now
**byte-identical to the start of this session**.

## One real thing was underneath it

`scan_param_whole()`'s own comment said:

> llapi_scan_changelog() has no such helper because
> LLAPI_SCAN_CL_PARAM_MIN_SIZE reaches through its last pointer.

That is **not correct**.  The changelog minimum reaches through
`sc_mdtname` at offset 40, but `sc_user` (40), `sc_mnt` (48) and
`sc_stats` (88) are all pointers past it, and its copy was raw:

    memcpy(&scl, sc, sc->sc_size);

`sc_user` and `sc_mnt` are dereferenced as strings.  So the hazard the
AI described was real -- on the *other* parameter struct, the one
nothing defended.

Fixed the way the series already chose, rather than the way I first
reached for: `scan_cl_param_whole()` rounds down, matching
`scan_param_whole()`.  Verified by arithmetic against the real header:

    sizeof=96  sc_mdtname@32 sc_user@40 sc_mnt@48 sc_stats@88  min=40
      sc_size 41..47 -> copy 40      (sc_user would have been torn)
      sc_size 49..55 -> copy 48      (sc_mnt)
      sc_size 89..95 -> copy 88      (sc_stats)

Finding 2's pre-existing half is fixed too: 68094's comment no longer
names fields and functions that arrive three and five patches later.
A patch has to read correctly at its own place in the series.

## Lab

`~/lustre-r18`, ldiskfs, MDSCOUNT=2 OSTCOUNT=2, rebuilt with the
reverted `sp_size` and the new changelog round-down:

    llapi_scan_test -d /mnt/lustre            11 of 11 pass
    sanity 56El 160aa 160ab 160ac 160ad       all PASS

(The lab's `liblustreapi_pfind.c` was reverted with a targeted diff, not
a file copy -- that branch carries 68340's memsets.)

## The lesson, in one line

The AI comment quoted code; the tree had moved on.  **Read the tree at
the line the fix would touch, not the line the comment quotes** -- and
when a fix is meant to close a hazard, measure it against the *unfixed*
build, or the measurement only proves the new code runs.

18 changes, 18 Change-Ids.  checkpatch: 0 errors on both touched
commits.  Builds under `-Werror`.
