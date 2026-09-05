# lreview on 68416 — four findings, all four fixed

**4 findings, severity low, 3.6M tokens, $4.32** — the cheapest run so
far, and it found no correctness bug in the new call: *"the pathname
composition, the fd handling on every error path and the -ESTALE guard
all trace clean."*  Three documentation gaps and one allocation.

## `(1)` — the hazard the sibling documents and this one did not

`llapi_scan_fid()` takes `@mnt_fd`, and **nothing in it can check that
the mount belongs to the same filesystem as `@fid`**.  FID sequences are
not unique across filesystems, so a mount of the wrong one resolves the
FID and gathers a **complete record for an unrelated object, rc 0,
nothing said**.

The `-ESTALE` guard does not catch it: the FID the gather reads back is
numerically the one that was asked for, so the memcmp passes.

`llapi_scan_rec_path()` already carries this warning — and it only
formats a name, where this one opens and gathers, so the caller has more
to lose.  Now documented here too, and `sp_fsname` — which is
`llapi_scan_device()`'s answer to the same hazard — is named in the
ignored list, so a caller that set it is not left thinking it is
honoured.

## `(3)` and `(4)` — `-EINVAL` does not only mean "you passed rubbish"

`mdt_fid2path()` and `ofd_fid2path()` answer `-EINVAL` for a FID that
`fid_is_namespace_visible()` excludes, and `llapi_fid2path_at()` passes
it out unchanged.  A device scan hands out plenty of those — every
`O/<seq>/LAST_ID` and its kind — so this is the live case for exactly
the consumer `llapi_scan_fid()` is aimed at.

`llapi_scan_rec_path()` documents it and tells the caller to read it as
*"this object has no name"*.  The kernel-doc and man page here presented
it as purely a caller mistake, so a consumer following this page would
have read a normal answer as a bug in its own argument handling.

Fixed in the kernel-doc `Return:` block and in the man page.  The man
page had **two** `-EINVAL` entries — RETURN VALUES and ERRORS — and the
finding named only the second; both now say it, the first pointing at
the second rather than repeating it.

## `(2)` — 70KB of calloc per object, before deciding whether to use it

`common_param_init()` allocates the `lmd` and `lmv` scratch — some 70KB
— and it ran **before the filter and regardless of the demand mask**, so
it was paid for every object the filter discards and every object a
name-only `sp_want` never gathers.

`lustreapi.h` promises *"A scan wanting nothing outside
LLAPI_SCAN_DIRENT_MASK performs no ioctl per object"*.  It now does no
allocation either: the init moved inside `if (want & LLAPI_SCAN_MDT_MASK)`,
which is where the `open()` already sits for the same reason.

Verified before moving it, rather than trusting the suggestion:

- nothing between the old site and the gather block touches `param` —
  checked line by line over the whole range;
- `out:` calls `find_param_fini(&param)` unconditionally, and that
  function tests every pointer before freeing, so a path that never
  reaches the init leaves a `{ 0 }` struct it handles.

## Recorded, not fixed: no test drives `llapi_scan_fid()`

The reviewer's whole-patch point.  `llapi_scan_namespace()`,
`llapi_scan_device()` and `llapi_scan_changelog()` each landed with a
test binary **and** a `sanity.sh`/`conf-sanity.sh` subtest driving it;
`llapi_scan_fid()` lands with a man page and nothing exercising it.

It suggests the cases worth having: the root FID, a trailing slash on
`mnt_path`, a name-only `sp_want`, a filter returning 1, and an unlinked
FID answering `-ENOENT`.

That is the **second** patch in this series found to be missing its own
test — 68415's `llapi_scan_changelog_test` is built but nothing runs it.
Both are noted for a test patch of their own rather than grown into
these; recording them together because the pattern is now the point, not
the individual gap.

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2, with the allocation move applied:

    llapi_scan_test -d /mnt/lustre           11 of 11 pass, 0 fail
    sanity 56El 160aa 160ab 160ac 160ad      all PASS

160aa and 160ac drive `llapi_scan_fid()` for every resolved candidate,
which is the path the move is on.

checkpatch 0 errors; `checkpatch-man` clean on `llapi_scan_fid.3`.
18 changes, 18 Change-Ids.
