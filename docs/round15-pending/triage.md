# Round 15 triage — the AI sweep of 2026-08-30

56 unanswered AI comments on the current patchsets, across 15 of the 19
changes (68157, 68158, 68231, 68340 drew none).  Every one below was checked
against the tree before being classified.

## Defects (verified in the tree)

| change | where | what |
|---|---|---|
| 68159 | `find_lmm_fits()` V1/V3 arm | a directory's default layout has `lmm_stripe_count` set and **no** `lmm_objects[]`, so 32 bytes with count 4 is rejected, and every such directory answers `--stripe-*`/`--pool` off `find_lmm_set_default()`'s forged filesystem default |
| 68159 | same switch | `LOV_MAGIC_SEL` and `LOV_USER_MAGIC_SPECIFIC` fall to `default: return false` — both are written by lod and only a target scan ever reads them, so the same forged default |
| 68288 | `find_decide()` print arm | `fid2path` answers **-EINVAL**, not -ENOENT, for a FID that is not namespace-visible; an OST's `LAST_ID` reaches it (`scan_classify()` tests `LMAC_FID_ON_OST` before `fid_is_last_id()`), so `lfind --device OST --fid2path` errors and exits non-zero on a healthy filesystem |
| 68415 | `scan_cl_resolve()` shortcut | `LLAPI_SCAN_TYPE` is in `SCAN_CL_EVENT_MASK` but `scan_cl_mode()` answers it for only four record types: `FID|TYPE` + `_RESOLVE` opens nothing, so `-type` is undecided for every CL_CLOSE/TRUNC/SETATTR |
| 68415 | `scan_cl_absorb()` | `co_pfid` is assigned from every event while `LLAPI_SCAN_PARENT` is only OR'd in, so create+close delivers the bit over a zeroed parent |
| 68415 | `scan_cl_object()` | a namespace record with no target object carries a **zero** `cr_tfid` (`mv a b`), and every one of them coalesces into one cache entry — only the last is delivered, and with `_F_CLEAR` the rest are purged |
| 68416 | `llapi_scan_fid()` | the gather runs against the pathname, not the FID: unlink+recreate between `fid2path` and the gather returns 0 with a record for a different object |
| 68417 | `find_device_supported()` | `fp_since_kind` is not refused, and `llapi_find_device()` never reads it — `lfind --local --since 2h` silently scans everything |
| 68418 | `find_changelog_supported()` | a changelog record never carries `LLAPI_SCAN_MODE`, so `fp_get_lmv` is 0 and `--mdt-count`/`--hash-type`/`--hash-flag` are never evaluated, and are not refused either |
| 68418 | `find_since_cand_cb()` | `fc_gather_all` is false and `fss_want` comes from `find_want(param, 0, false)`, so `-printf` under `--resolve` reports the MDT's lazy size and `DEFAULT_PROJID` |
| 68418 | same | `fc_fdp` is NULL and PROJID is masked out of `fss_want`, so `--changelog --resolve --projid` fails on the first record and searches nothing |
| 68418 | `llapi_find_since()` | `fss_path_rc` is written and never read — `llapi_find_device()` has the `rc = st.fds_path_rc` line, this one does not, so a run that resolved nothing exits 0 |
| 68419 | `lfs.c` path loop | `llapi_find_since()` runs once per path and each call rewrites the cookie, so the second path reads back the first's anchor and reports empty |
| 68156 | `enum llapi_scan_class` + `llapi_scan_device.3` | `LMAI_AGENT` is the **DNE** remote-entry agent inode, not HSM: only `osd_create_local_agent_inode()` and `osd_create_agent_object()` set it |
| 68416 | `llapi_scan_fid.3` EXAMPLE | `llapi_root_path_open()` takes two arguments; the example passes four and `mnt` is never assigned |

## Real but small (code)

- 68094 `ss_stop_rc` comment: `ss_filter`'s negative lands there too, via `goto stop`.
- 68094 trailing slash: `llapi_scan_namespace("/mnt/lustre/dir/")` gives the root record an empty `sr_name`.
- 68288 / 68416: root FID resolves to `"/"`, so both path builders compose `<mnt>//`.
- 68415 `co_jobid = strdup()` and `scan_cl_strdup()` failures leave the validity bit set over NULL.
- 68415 `scan_cl_held_first()` runs before the batch test: an O(sc_max_cached) walk per record under `_F_CLEAR|_F_COALESCE`.
- 68415 open-by-FID is a real `O_RDONLY` open, so resolving an event on a device node opens the driver.
- 68418 the `-projid` arm of `find_changelog_supported()` is unreachable: `find_check_lmm_info()` already ends with `fp_check_projid`.
- 68419 `--since-cookie /tmp/nodir/job.ck` reads as a first run; the writability check belongs in the pre-pass.
- 68419 no `fsync()` before the rename, so a host crash can leave an empty cookie that parses as "no anchors".
- 68419 the message names `anchor + 1`, the file holds `anchor`.
- 68095 the `*dp = d` writeback is a no-op (nothing assigns through `dp`) and its comment is wrong — **already removed two patches later, in 68157**.

## Doc / test / style

- 68160 `lfind.8` is dated 2026-08-19; `lfs-find.1` in the same patch is 2026-08-28.
- 68160 the `EBUSY` / ZFS paragraph describes `libscan_zfs.c`, which arrives in 68163 — a forward reference.
- 68163 `.BR -h ", " --help` lost its `\-` escapes.
- 68415 `llapi_scan_changelog.3`: `sr_event_prev` is the previous index **for this FID**.
- 68414 the mask comment contradicts itself; past tense fixes it.
- 68413 the `lrh_len` comment: post-LU-19296 servers write 80 bytes, so `cur_name` is inside the record.
- 68413 the test asserts only successes; a negative case would pin the widened gate.
- 68420 commit message says `--resolve` "does not assert the answer", but 160ab does.
- 68420 `lfs-find.1`: `--xattr` missing from the refusal list; the three examples sit under AVAILABILITY instead of EXAMPLES.
- 68420 test suggestions: a named MDT for `--changelog`, and a DNE `Test-Parameters` line.
- 68156 e2fsprogs already has `ext2fs_get_stat_i_blocks()`, `ext2fs_inode_includes()`, `EXT4_EPOCH_MASK`.
- 68156 `EXT2_ET_BAD_BLOCK_IN_INODE_TABLE` is unreachable (nothing calls `ext2fs_read_bb_inode()`); a media error gives `EXT2_ET_NEXT_INODE_READ` -> -EIO, which the man page says cannot happen.
- 68156 `so_external` and `tt_objects` are filled and never read.
- 68094 `scan_rec_dirent()`/`scan_rec_gather()` lack the file's `llapi_scan_` prefix (both are local per `liblustreapi.map`).
- 68415 `LLAPI_SCAN_CL_F_KNOWN` is public where `_KNOWN_NS`/`_KNOWN_DEV` are internal.
- 68416 the commit message claims the resolver moves onto `llapi_scan_fid()`, which nothing calls yet.
- 68416 a `struct statx` where only `st_mode` is set; the default-mask copy is duplicated.
- 68416 a positive `sp_filter` return escapes `llapi_scan_fid()` as a non-zero rc.

## Needs the user's call

1. **`lfind` as an installed name** — glibc ships `lfind(3)`, so `man lfind` is shadowed, and the name reads as a contraction of `lfs find`.
2. **`LLAPI_SCAN_LMV` in the default demand mask** — it costs one ioctl per directory (eight syscalls off Lustre), against a header that says the default excludes what costs an ioctl per object.
3. **`--since-cookie` with several paths** — refuse more than one path, or read once / write once around the list.
4. **The ZFS/EBUSY paragraph** — move it to 68163, or leave the forward reference.
5. **`sp_padding` must-be-zero** — give the reserved bytes the guarantee `sp_flags` has.

## What was done (2026-08-30)

51 fixed, 5 declined.  The declines, with reasons, are in `replies.md`:
`scan_rec_*` naming (both symbols are local per `liblustreapi.map`), the
e2fsprogs helpers (`ext2fs_get_stat_i_blocks()` is not the same sum), the
`lfind` name (the user's call), `LLAPI_SCAN_LMV` in the default mask (the
wording changed instead -- the ioctl is per directory, not per object), and
the `EXT2_ET_NEXT_INODE_READ` half of the ldiskfs skip comment (nothing
advances past it, so it still ends that target's scan; the man page says so
now and lists -EIO).

Three defects the round found that no comment named:

- `scan_classify()` tested `LMAC_FID_ON_OST` before `fid_is_last_id()`, and
  `osd_object_create()` sets that flag for a LAST_ID -- so on an OST the
  target's own counter was classified as a data object.  That is the root of
  68288's -EINVAL, not just a symptom of it.
- `EXT2_ET_INODE_CSUM_INVALID` and `EXT2_ET_INODE_IS_GARBAGE` were ending a
  worker's whole scan through the `-EIO` arm.  Both leave the scan advanced,
  so both are skips.
- 68095's `*dp = d` writeback was already removed two patches later, in
  68157; now neither patch carries it.

Verification: checkpatch clean on the round's delta, all 16 commits build
individually (userspace), and the lab run is `lab-r15b` -- base + 68413 +
68414 + the 16, 18 patches, on `rhel9.7-server-mgs-mds-clone`.
