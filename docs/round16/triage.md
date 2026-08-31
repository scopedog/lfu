# Round 16 triage — the AI sweep of 2026-08-30/31

64 unanswered AI comments on the current patchsets, across 16 of the 19
changes (68158, 68231 and 68340 drew none).  Every one below was checked against
the tree before being classified.

## Defects (verified in the tree)

| change | where | what |
|---|---|---|
| 68156 | `scan_backend_load()` | glibc clears the pending dlerror on every successful `dlsym()`, so the single `dlerror()` after five `SCAN_DLSYM()` can only report the last.  A plugin missing `sb_close`, `sb_worker_init` or `sb_worker_fini` is accepted and called through NULL |
| 68156 | `scan_classify()` | `fid_seq_is_root(seq)` accepts the whole FID_SEQ_ROOT sequence; `fid_is_namespace_visible()` uses `fid_is_root()`, exactly one FID.  The echo-client root classifies CLS_VISIBLE where the MDT's own test would not, and the man page claims the two agree |
| 68156 | `scan_errcode()` | `EXT2_ET_BAD_MAGIC` is above `EXT2_ET_BASE`, so a ZFS target, a raw LUN or a non-ext image answers -EIO, documented as "a read of the inode table failed" |
| 68159 | `find_lmm_foreign_fits()` | `lov_foreign_md_size()` adds in `__u32`, so an `lfm_length` above 0xFFFFFFEF wraps and the bounds test succeeds.  Not an over-read today; the block's own comment says nothing here trusts a field before its bytes are accounted for |
| 68159 | `find_device_prefilter()` | an object whose linkea gave no name is handed to `find_prefilter()` with `sr_name = ""`, so `--name X` drops every OST object and `! --name X` keeps every one.  Neither is an answer the target gave |
| 68163 | `scan_zfs_scan_chunk()` | `so_valid \|= LLAPI_SCAN_SO_PROJID` sits outside the `if`, so a `sa_lookup()` that failed on an unreadable spill block claims projid 0 is the answer |
| 68163 | `lustre-build-zfs.m4` | `${zfsinc}` is the first candidate in the probe loop while the comment above says it cannot pass — either a compile probe for nothing, or a layout that passes without the mandatory `-DLIB_ZPOOL_BUILD` |
| 68288 | `conf-sanity.sh` 165 | `grep -q "^\[0x" $got` cannot fire: `$got` was built by piping through `grep "^$MOUNT/$tdir/"`.  Runs against `$got.raw` |
| 68288 | `find_decide()` print arm | a FID from another filesystem answers **-ENOENT** (`fld_handler.c:269`, `mdt_handler.c:8005`), not -EPERM, so it is already counted as nameless.  The comment, the commit message and `lfind.8` all claim the wrong-filesystem case reaches the error arm |
| 68413 | `mdd_changelog_user_lookup_cb()` | `cur_name` comes off disk with no guaranteed NUL in its 16 bytes; `mdd_changelog_name_check_cb()` bounds the same field, this `strcmp()` does not |
| 68415 | `scan_cl_resolve()` | `LLAPI_SCAN_SIZE`/`BLOCKS` are set whenever the `fstat()` succeeds, but the glimpse open runs only for `sc_want == 0` or SIZE/BLOCKS, and can fail.  `sc_want = LLAPI_SCAN_MTIME` reports the MDT's lazy size as strict; `LLAPI_SCAN_LAZY_SIZE`/`LAZY_BLOCKS` exist for exactly that value |
| 68415 | `scan_cl_object()` | `cr_uid`/`cr_gid` are the acting client's credentials (`mdd_changelog_ns_store()` passes `uc->uc_uid`), not the object's owner, which is what `sr_uid` means everywhere else and what `-uid`/`-user` matches.  root touching alice's file delivers `sr_uid = 0`, and UID/GID being in `SCAN_CL_ALWAYS_MASK` means a resolve cannot correct it |
| 68415 | `llapi_scan_changelog_param` | `sc_padding` is neither documented nor checked, unlike `sp_padding` in the two sibling entry points, so the bytes can never be reclaimed |
| 68416 | `llapi_scan_fid()` | the bounded copy skips `scan_param_padding_ok()`, which both siblings run — the same block is refused by them and accepted here |
| 68417 | `llapi_find_since()` | the subtree root is `realpath(path)` but the mount is looked up from `path` as spelled.  An absolute path through a non-Lustre symlink gives -ENODEV; a relative path under `$MOUNT2` takes the *first* mount of that fsname and every object is then rejected — prints nothing, exits 0 |
| 68418 | `find_decide()` | with `fc_fid_when_lost` set, `fss_unresolved` is never incremented, so the "N objects have no pathname and are named by FID" warning — the only thing telling a user that some lines are FIDs — can never print |
| 68418 | `find_since_cand_cb()` | an object gone between its event and the lookup is re-run through `find_changelog_rec_cb()` with the bare record, but `--resolve` has already let `-size`, `-blocks`, `-perm`, `-links`, `--attrs`, the layout options and `-printf` past the refusal.  Those are then answered from `find_rec_to_lmd()`'s zeroes and `find_lmm_set_default()`'s forged layout |
| 68418 | same | that `rc == -ENOENT` test cannot tell `llapi_scan_fid()`'s own "no longer resolves" from one the callback returned: `find_get_projid()` answers -ENOENT when the open fails, so a per-object failure under `--resolve --projid` is counted gone and the record run twice |
| 68419 | `find_device_supported()` | `fp_since_cookie` and `fp_changelog_mdt` are not refused, and `llapi_find_device()` never reads them: `lfind --local --since-cookie job.ck` scans, prints, never touches the cookie, and exits 0 — the case the `fp_since_kind` refusal beside it exists for |
| 68419 | `llapi_find_since()` | the cookie is rewritten on `rc == 0` from the scan loop, before `fss_path_rc` is folded into `rc`.  A run that dropped matches on a transient MDT error exits non-zero *and* has advanced the anchor past those records, so a rerun never sees them |
| 68419 | `find_cookie_read()` | `%llu` matches as if by `strtoull()`, which negates: an index of `-2` becomes 0xfffffffffffffffe and the run scans from an index nothing matches.  The MDT number is already sign-checked for the same reason |
| 68419 | `find_cookie_check()` | the probe is `fopen(cookie, "a")`, but the write is `<cookie>.new` + rename, which needs write permission on the *directory*.  A cookie in a root-owned 0755 directory passes the pre-pass and fails EACCES after every match has been printed |
| 68420 | `lfs-find.1` + `sanity.sh` 160ad + the refusal message | **`lfs find` has no `--hash-type` and no `--hash-flag`.**  `-H`/`--mdt-hash` is what sets `fp_hash_type` and `fp_check_hash_flag`.  So the man page names options that do not exist, the refusal message names them back to the user, and the new test exits non-zero from getopt rather than from the refusal — it would keep passing if the option were dropped from the list entirely |
| 68420 | `lfs-find.1` | those three sit in the list of options `--changelog` refuses, but `find_changelog_supported()` returns before that test under `--resolve`, where the lookup supplies the LMV and they are answered |

## Real but small

- 68094 `scan_rec_gather()`: the comment's reason ("the lstat fallback never writes lmd_fid") stopped being true in this same patch — `convert_lmd_statx()` now clears it, and that is the fallback's last step.  The clear here is redundant.
- 68094 `llapi_scan_namespace.3`: PROJID is listed beside the fields a stat always answers, but it is outside the default demand mask.
- 68094 test10: "pass for none of them" holds for LAYOUT only — MDT_INDEX, PROJID and HSM are outside the default mask and LMV needs a striped directory, so three of the five bits are clear on Lustre too.
- 68095 `find_prefilter()`: the comment names `--name` and `-type`; the function also rejects any non-directory for `--mdt-count`/`--mdt-hash`.
- 68156 `SCAN_LMV_BUF`: "a header plus one entry per stripe" — `scan_lmv_to_user()` writes no entries, only the foreign copy needs the room.
- 68156: the `scan_linkea()` comment sits above `scan_lmv_to_user()`, and the `struct scan_worker` comment above `SCAN_LMV_BUF`.
- 68160 `lfind_target.lt_name[64]`: an osd service name is `char od_svname[MAX_OBD_NAME]` (128) on the kernel side.
- 68160: `lfs_find_parse()` prints its errors with `argv[0]`, so `lfind` gets `lfind /usr/sbin/lfind: ...`.
- 68160: the "name one target" message covers both "none" and "more than one", and omits the bare DEVICE form.
- 68160: the per-target header is user-visible and `lfind(8)` does not mention it — nor that it goes to stderr, nor that it appears only when nr > 1.
- 68163 `scan_zfs_label()`: the header comment says the never-mounted separators do not occur in the property; the body checks all four, and it is right — `zfs_set_prop_str()` writes `ldd_svname` straight through.
- 68163 `llapi_scan_device.3`: -EIO as "a read of the target's inode table failed" is ldiskfs's vocabulary; the ZFS backend answers it from `scan_zfs_open()` and `dmu_object_next()`.
- 68288 `llapi_scan_rec_path.3` + kernel-doc: -EINVAL also means "this object has no name", which is why `find_decide()` treats it alongside -ENOENT.  The EXAMPLES fragment counts only -ENOENT.
- 68415 `llapi_scan_changelog.3`: a callback value that stops the stream is folded under "<0"; a positive one comes back unchanged, as `llapi_scan_namespace.3` says in its own entry.
- 68415 `scan_cl_flush()`: under `_F_FOLLOW` `sl_now` only moves when a record arrives, so on a quiet filesystem `sc_min_age` stops elapsing and `_F_CLEAR` holds the backlog for as long as the quiet lasts.
- 68416 `llapi_scan_fid()`: the parent open runs before `sp_filter`, so a filter that rejects the object still pays one open RPC per FID — `lustreapi.h` says the filter is called before any I/O.
- 68417 `find_since_rec_cb()`: `checked_type` is filled by `find_since_pick()` and then hard-coded 0, the one place the three callbacks disagree.
- 68417: `--since` prints absolute paths where the same walk prints the path as spelled (`./sub/f` vs `/mnt/lustre/sub/f`).
- 68418: a record with no pathname skips `find_since_under()`, so under a named subtree the gone objects of the whole filesystem are still emitted.
- 68418: the `fc_path` comment is stale now that it is set from `rec->sr_path`.
- 68419/68420/68417: three Test-Parameters lines name `ONLY=56`, which has no `--since`/`--since-cookie` coverage at all.
- 68420 `lfs-find.1`: the escaped newline joins two source lines into an ~87-column `.EX` line, which groff will not wrap.
- 68420 `sanity.sh` 160ad: `${tdir}-other` lives outside `$tdir` and survives an early error; 160ac already `stack_trap`s its cookies.

## Commit messages

- 68094: subject is a noun phrase (declined, below); "the V1 case had its own clear and no longer needs one" describes a removal the patch does not make — the parent has no `lmd_fid` in `lustre/utils` at all.
- 68095: never names `find_prefilter()`, `find_want()`, `scan_rec_dirent()` or `scan_rec_gather()`; two of the four deltas are user-visible bug fixes and want a `Fixes: 6b8e97b76c47` trailer, as the sibling LU-20624 carries.
- 68157: "One line goes rather than moves" — the parent's `cb_find_init()` has no store through `dp`; nothing in the series ever removed one.
- 68163: reads as though conf-sanity 165 merely skips, where the diff rewrites ~50 lines of it.
- 68288: the wrong-filesystem claim, as above.
- 68413: "the half of this fix that has to walk past a plain record" — the old callback's first `||` clause already skipped a plain record before `strcmp()`, so a name lookup behaved identically before and after.  Only the `cf_user_id != 0` path changed.
- 68414: "reachable only through `llapi_changelog_start_user()`" does not hold.  `llapi_convert_str2mask()` seeds from `*oldmask` when the first token carries an operator, and `lfs_changelog()` seeds it with CHANGELOG_DEFMASK, so `lfs changelog --user clN --mask=-mark,-creat` reaches the disjoint case from the shell.  A regression test is therefore writable.
- 68418: several paragraphs read as a record of what changed between patchsets rather than what the change does.

## Declined

- 68094 subject style: the body's first sentence names `llapi_scan_namespace()`, and `git log --grep` searches the body.
- 68095 the dead `if (ret == -ENOTTY) lustre_fs = 0;`: carried over unchanged from upstream's `cb_find_init()`; it is dead only because of `get_lmd_info_fd()`'s own fallback, which is a separate contract.  The `!lustre_fs` arm below is still reached — `find_device_cb()` sets `fc_lustre_fs = 0`.
- 68095 the `--foreign` shortcut skipping `get_projid()` and the lstat: `goto print` is upstream's, unchanged since before this series.  The commit message is narrowed instead.
- 68415 `_F_FOLLOW` + `sc_min_age`: a wall-clock fallback needs a timeout on `chlg_read()`, which is a kernel-side change.  Documented in the man page and the header instead.

## Autotest

Every failure this round is in the known-noise set: sanity-pcc 1c/1d on both
backends, sanity-quota 30 and 86, recovery-small 155 and 24b, racer and
replay-dual timeouts, sanity-dom 36d, sanity 45, sanity2 63c, sanity-lfsck,
LU-20598 sanity-sec (17 more).  Two to watch rather than fix:

- **68288 sanityn test_42g** "stat must succeed", flagged NEW unique for this
  branch in 30 days.  68288 touches `liblustreapi` only; retest rather than
  chase.
- **68094 sanity-scrub** in review-dne-zfs-part-7 — still the browser job from
  the 08-30 list; the Maloo session 302s to /signin.
