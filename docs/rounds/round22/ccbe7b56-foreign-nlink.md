# 68159 `ccbe7b56` — `--links` drops a foreign directory on a device scan

2026-09-08. First of the seventeen untriaged AI comments. **Verified,
reproduced on a real device scan, fixed, and the arms proven against the
unfixed build.**

## The claim, and every step of it against the tree

`struct lmv_foreign_md` (`lustre_idl.h:2404`) is

    __u32 lfm_magic; __u32 lfm_length; __u32 lfm_type; __u32 lfm_flags;

and `struct lmv_user_md_v1` is

    __u32 lum_magic; __s32 lum_stripe_count; ...

so **`lfm_length` and `lum_stripe_count` share offset 4**. `find_decide()`'s
nlink gate reads the second name for the first byte:

    if (param->fp_nlink && S_ISDIR(lmd->lmd_stx.stx_mode) &&
        (param->fp_lmv_md->lum_stripe_count != 0))
            decision = 0;

`decision = 0` means "this needs a stat". Every other LMV-consuming arm in
the function — `--mdt-count`, `--hash-type`, `--hash-flag` — tests
`lmv_is_foreign()` first; this one does not.

The gate is **verbatim upstream** (`5afbab284e:liblustreapi_pfind.c:2892`),
so the misread is not ours. What this series adds is a caller with nothing
to stat: on a device scan there is no path and no descriptor, so
`find_decide()` marks the record undecided and drops it — **out of both
`--links N` and `! --links N`**, the same shape as round 22's `--projid 0`
defect.

`find_device_want()` (`:2586`) asks for `LLAPI_SCAN_LMV` precisely because
`fp_nlink` is set, and `scan_lmv_to_user()` copies a foreign LMV through
with its real `lfm_length`, so the path is reachable rather than theoretical.
`STATX_NLINK` is in both `LLAPI_SCAN_MDT_MASK` and `LLAPI_SCAN_WANT_KNOWN_DEV`,
so the record could have answered `--links` directly all along.

## Measured on the lab

`rhel9.7-server-mgs-mds-clone`, `~/lustre-spgot` at the stack tip
(`6e7f272951`), ldiskfs, MDSCOUNT=1. Fixture: two foreign directories built
with `lfs setdirstripe --foreign=none --xattr=abcdef` (so `lfm_length` is 6),
one plain directory, one file — all under `/fgn`.

The **walk** answers correctly, which is what has hidden this:

    $ lfs find /mnt/lustre/fgn --links 2
    /mnt/lustre/fgn/fdir2
    /mnt/lustre/fgn/plain
    /mnt/lustre/fgn/fdir

The **device scan**, unmounted, on the same objects:

| arm | unfixed | fixed |
|---|---|---|
| no `--links` | fgn, f0, fdir, fdir2, plain | same |
| `--links 2` | **plain** | fdir, fdir2, plain |
| `--links 5` | fgn | fgn |
| `! --links 2` | fgn, f0 | fgn, f0 |

`fdir` and `fdir2` are in **neither** answer unfixed. Fixed, the two answers
partition the five objects.

## The fix

Guard the gate the way its siblings are guarded — one line, in
`find_decide()`:

    !lmv_is_foreign(param->fp_lmv_md->lum_magic) &&

Chosen over emptying the buffer in `find_rec_to_lmv()` because `--foreign`,
`--foreign-type` and `-printf %LF` all need the foreign LMV to still be
there, and because the gate is the thing that is wrong: a foreign directory
has no stripe count to read. It also drops a pointless stat per foreign
directory on the walk side, which is the only thing that ever happened there.

Safe against a stale magic on the walk: `get_lmd_info_fd()` re-seeds
`lum_magic` to `LMV_USER_MAGIC` or `LMV_MAGIC_V1` before **every**
`LL_IOC_LMV_GETSTRIPE` (`:148`/`:150`), and `find_rec_to_lmv()` memsets the
header before every record, so the guard can only fire on an LMV that really
is foreign.

The AI's second half — that `find_rec_to_lmv()`'s comment claims both
scanners hand over an `lmv_user_md` — is true and now says otherwise.

## Arms

`tests/lab-r18/09-arms-foreign-links.sh`, run both ways on one fixture:
**unfixed 3 pass / 2 fail, fixed 5 pass / 0 fail.** Its first arm asserts the
fixture before the rest read anything into it, and its last asserts that
`--links 2` and its negation add up to the whole — the arm that catches an
undecided object, which a one-sided test would not.

## Noticed in passing, NOT fixed here

`-printf %Lc` on a foreign directory prints `lfm_length` as a stripe count,
through the same aliasing (`liblustreapi_pfind.c:1777`). That code is
upstream unchanged (`5afbab284e:liblustreapi.c:3024`) and it is a wrong
number printed, not an object dropped, so it is not this patch's to carry.
Worth its own ticket upstream alongside the doubled-separator one.
