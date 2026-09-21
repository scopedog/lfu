# Round, 2026-09-21 — the Gerrit AI comments of 09-20/21

Eleven comments arrived on five changes between 2026-09-20 15:00 and
2026-09-21 01:00. Nine taken, one declined, one left to its own change.

The stack fixes are transforms in [`r0921fix.py`](r0921fix.py), driven by
[`r0921drive.py`](r0921drive.py) over `b7b1332a42..r0920-tip`. New tip
**`r0921-tip` = ea8bd797c5**, 26 commits; `backup/fix-0921-pre` = c00708148b
(the r0920 tip). 68414 and 65026 are single commits and were amended in place.

## 68094 PS21 — the attrs gate

`scan_rec_mdt()` set `LLAPI_SCAN_ATTRS` when `stx_attributes_mask != 0`.
Verified in the tree: `ll_dir_ioctl()` (llite/dir.c:2486) fills that mask with
a build-time constant — `STATX_ATTR_IMMUTABLE | STATX_ATTR_APPEND`, plus
`STATX_ATTR_ENCRYPTED` under `HAVE_LUSTRE_CRYPTO` — before it reads anything
out of the reply, so on Lustre it is never zero and the bit was set for every
object. What the MDT declares is `OBD_MD_FLFLAGS`, which
`mdt_pack_attr2body()` (mdt_handler.c:823) sets only for `LA_FLAGS`; it
reaches the library in `lmd_flags`, which `scan_rec_mdt()` already holds as
`flags` for the LAZY_ bits. The gate is now that bit; the value is still
masked down to `stx_attributes_mask`, which is what keeps `FS_INDEX_FL` from
reading as `STATX_ATTR_AUTOMOUNT`. The man page entry said "the bits the
server declared it supports" and says the same thing the code now does.

No change for `lfs find`: `find_check_attrs()` and `printf_format_string()`
read `lmd_stx.stx_attributes_mask & stx_attributes` directly, not the valid
bit. What changes is the record's contract — `stx_attributes == 0` is now
distinguishable from "not answered", which is what `lfsr_valid` is for.

## 68095 PS22 — `! --foreign` costs a getattr again

Upstream's `goto print` for an unstriped directory under `! --foreign` sat
*before* `get_lmd_info_fd()` (verified against b7b1332a42's
liblustreapi_pfind.c), so the object printed on the LMV answer alone. With
the record the shortcut moved below `scan_rec_gather_finish()`, which is the
`LL_IOC_MDC_GETINFO_V2` getattr: one MDT RPC per unstriped directory became
two. `find_foreign_accepts()` now takes it before the gather, and `-printf`
is excluded because the attributes it prints are exactly what that RPC
fetches. The pre-split trees (68095, 68156) jump to their own `print:`
label; from 68157 on, `cb_find_init()` jumps over the gather to `decide:`
and `find_decide()`'s existing shortcut does the printing.

## 68156 PS22 — three

1. **`.gitignore`** has a line for every other binary in `THETESTS`,
   including `/llapi_scan_test`; `/llapi_scan_device_test` was missing.
2. **A striped directory's size.** `ll_dir_ioctl()` drops `OBD_MD_FLSIZE`
   and `OBD_MD_FLBLOCKS`, and with them `STATX_SIZE` and `STATX_BLOCKS`, for
   a striped directory, because the client aggregates both across the shards.
   `scan_size()` took the `!S_ISREG` arm and answered the master inode's own
   numbers with both bits set, so one directory answered "not known" from
   `llapi_scan_namespace()` and a concrete number from `llapi_scan_device()`.
   Answer-equivalence is the prerequisite for `llapi_scan()` choosing a
   source, so the device scan now withholds them too:
   `scan_lmv_is_striped()` tests `trusted.lmv` for `LMV_MAGIC_V1`, which is
   what `lmv_dir_striped()` tests on the client side — a shard's
   `LMV_MAGIC_STRIPE` and a foreign LMV are neither. The size demand pulls
   `trusted.lmv` with `trusted.lov` and `trusted.som` so the test can be
   made; on ldiskfs that is a lookup in xattrs already read in one pass
   (`ext2fs_xattrs_read_inode()`), on ZFS it can cost a spill lookup for an
   object that has an xattr dir and no SA copy.
3. **The 2.17.58 gate — declined.** The comment's premise is that the newest
   tag in the tree is v2_17_57. It is not: `LUSTRE-VERSION-GEN` has
   `DEFAULT_VERSION=2.17.58` and the series base describes as
   `v2_17_58-39-gb7b1332a42`, so `MDS1_VERSION` is 2.17.58 on a build from
   this tree and conf-sanity 300 runs.

## 68414 PS9 — two, both text

The commit message described an earlier revision of itself ("an earlier
attempt ... was removed after a control run showed it passing"); against
master there was never a two-absolute-mask test. The technical content is
kept as the reason the test is shaped the way it is. The `mdc_changelog.c`
comment's example — "a user allowed CREAT asking for MKDIR is owed no
records" — does not hold for masks that came from strings, which is the path
`lfs` takes: `cfs_str2mask()` seeds an absolute mask from `CHANGELOG_MINMASK`,
so both carry `BIT(CL_MARK)` and that user does get the MARK records. The
comment now names a relative mask, as the commit message already did.

## 65026 PS12 — four

1. **The message's list** covered two of three cases and never named the
   errno the signal case yields. Rewritten to the three the code tests.
2. **`-EINTR` for a signal-killed helper → `-EPROTO`.** Nothing catches it on
   the way out (`sptlrpc_sepol_get()` passes any non-zero rc straight up), so
   it surfaced as EINTR from whatever syscall drove the RPC with no signal
   delivered to that task, and a caller looping on EINTR would spin against a
   helper that stays dead. `-EPROTO` is what the branch above already uses
   for "the helper misbehaved". sanity-selinux 21d does not exercise the
   signal case, so nothing in the test moves.
3. **The 21d comment's first sentence** was stale: since 308b7fd2baf5
   ("LU-20551 tests: fix persistent sepol cleanup in sanity-selinux", ours,
   landed) test_21c cleans up with `set_param -P -d`, so it leaves no
   persistent entry. The `-P -d` call stays as belt and braces against a
   stale entry from an older run, which is what the comment now says.
4. **The `mdc_reint.c` leak — left to its own change.** Two returns in
   `mdc_create()` (`body == NULL` and `eadata == NULL`) run before
   `*request = req`, so the request and the import reference
   `ptlrpc_request_alloc()` took are never put. It is a real leak of the same
   shape this change fixes on the sepol paths, but on the reply-decode side
   and pre-existing; the reviewer said the same. Owed as its own patch.

## What was verified

- The whole 26-commit stack rebuilt per commit:
  [`build-sweep-0921.sh`](build-sweep-0921.sh), `build=0 hdr=0 tests=0` for
  all 26.
- `checkpatch.pl` on the three changed stack commits and on 68414 and 65026:
  no new findings (68094's "new file mode" and 68156's 82-column `echo` in
  conf-sanity are the two that were already there).
- **The lab A/B**, on the clone VM (2 MDTs, ldiskfs, `llmount.sh`), one build
  tree with the arms chosen by `LD_PRELOAD` of each arm's `liblustreapi` --
  the SONAME is the same, so the preload wins over the binary's RPATH, and
  each arm logs the library it actually loaded before any arm runs.
  A = `r0920-tip`, B = `r0921-tip`. Scripts and log: [`r21lab.sh`](r21lab.sh),
  [`r21lab2.sh`](r21lab2.sh), [`scanrec.c`](scanrec.c),
  [`r21arms.log`](r21arms.log). Ten checks, all as intended:
  - **68094.** The record is *identical* A/B over the live tree, which is the
    expected result and the reason this one cannot be measured on a live MDT:
    `osd_attr_get()` always fills `LA_FLAGS`, so `OBD_MD_FLFLAGS` is always
    set and both gates are always true. What the arms prove is that nothing
    regressed -- all 46 objects still carry `LLAPI_SCAN_ATTRS`, `--attrs
    Immutable` still finds the `chattr +i` file and nothing else in both arms
    -- and that off Lustre, where nothing declares flags, no object claims
    attributes. `scanrec.c` exists because `lfs find` reads `lmd_stx`
    directly: nothing it prints can show whether the valid bit was set.
  - **68095.** The answer is identical A/B (41 paths, sorted -- `lfs find`
    does not order its output, which the first run mistook for a difference),
    and the getattr RPCs drop from **63 to 21**: the 21 directories no longer
    pay one. Under `-printf` both arms pay 83 and print the same 41 lines,
    which is the case the shortcut deliberately does not take.
  - **68156.** With the filesystem stopped, a device scan of the MDT answers
    `%s %b` for the striped directory as **`4096 8` in A and `0 0` in B** --
    withheld, as the walk already withheld them (`scanrec` reports
    `size=unknown blocks=unknown` for it through the mount). An unstriped
    directory still answers `4096 8` and regular files `0 0` in both arms, so
    the change is bounded to the object it is about.
- Not yet: `lreview` on the changed commits. That gates the push.
