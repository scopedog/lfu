# Round 16 replies — one per AI comment, 64 in all

Style per [[gerrit-reply-brevity]]: "Done." where it was addressed, reasons
only where declined.  Change | comment id | reply.

## 68094 (5)

- `ba08702e` COMMIT_MSG:7 — Declining. The body's first sentence names
  `llapi_scan_namespace()`, and `git log --grep` searches the body, so it is
  findable; the subject stays as it is.
- `437f707f` COMMIT_MSG:38 — Right, the parent has no `lmd_fid` in
  `lustre/utils` at all. The sentence now says the clear is in
  `convert_lmd_statx()`, which covers both callers because it is the lstat
  fallback's last step and also runs on the V1-ioctl path. Done.
- `4f7537dc` llapi_scan_namespace.3:261 — Done, "where sp_want names it".
- `cbc850a2` llapi_scan_test.c:598 — Correct, only the layout would differ.
  The comment now says so, and the commit message's last paragraph with it.
  Done.
- `a9bd69df` liblustreapi_scan.c:323 — Done. Dropped the `lmd_fid` clear and
  reworded; `convert_lmd_statx()` is the fallback's last step, so it is the
  one clear that is needed.

## 68095 (5)

- `834a9405` COMMIT_MSG:9 — Done, the body now names `scan_rec_dirent()`,
  `find_prefilter()`, `find_want()` and `scan_rec_gather()`.
- `37e8c8ce` COMMIT_MSG:25 — Done, `Fixes: 6b8e97b76c47` added.
- `b1d3ab68` liblustreapi_pfind.c:2438 — Done, the third pre-filter is named.
- `4879db2b` liblustreapi_pfind.c:2586 — Agreed that `get_lmd_info_fd()`'s
  lstat fallback means -ENOTTY cannot reach here. Keeping it: the test is
  upstream's own, carried through this refactor unchanged, and it is dead
  only because of a contract that lives in another function. The
  `!lustre_fs` arm below is still reached — `find_device_cb()` sets
  `fc_lustre_fs = 0`.
- `44c30fa9` liblustreapi_pfind.c:2606 — The shortcut is upstream's `goto
  print`, unchanged by this patch, so the project id and the OST glimpse are
  skipped exactly as before. Narrowed the commit message to "this object's
  stat attributes" and said the early exit is unchanged, rather than
  altering the foreign shortcut inside a refactor.

## 68156 (6)

- `913a88a2` llapi_scan_device.3:36 — Done, NOTES now says `sp_max_depth` is
  inert here for the same reason `LLAPI_SCAN_F_STOP_ON_ERROR` is.
- `64a219d0` liblustreapi_scan_device.c:60 — Done, the comment now says a
  header and no stripe entries, and that only the foreign copy needs the room.
- `a0bb509e` liblustreapi_scan_device.c:175 — Real, and the man page made the
  same claim. Now tests `fid_seq_is_root(seq) && f_oid == FID_OID_ROOT`, which
  is `fid_is_root()` spelled out — that helper is server-side. The echo
  client's root no longer classifies CLS_VISIBLE. Done.
- `2ff01ea9` liblustreapi_scan_device.c:181 — Done, both comments moved onto
  what they describe.
- `895d84bd` liblustreapi_scan_device.c:708 — Confirmed; only the last
  `SCAN_DLSYM()` could be reported. All five pointers are tested for NULL now
  and the `dlerror()` dance is gone. Done.
- `b45d2921` libscan_ldiskfs.c:141 — Done, `EXT2_ET_BAD_MAGIC` maps to
  -EINVAL, which is already the "not a Lustre target" answer, and the man
  page's -EINVAL entry names it.

## 68157 (1)

- `559a2de8` COMMIT_MSG:16 — Correct, the parent's `cb_find_init()` has no
  store through `dp`, and no patch in the series removes one. Paragraph
  dropped. Done.

## 68159 (2)

- `08262cbb` liblustreapi_pfind.c:3257 — Done, subtracting instead of adding.
- `25a88a18` liblustreapi_pfind.c:3450 — Real. An object with no name at all
  is counted `fds_undecided` now rather than matched against the empty
  string, which is how an absent birth time and project id are already
  handled. Done.

## 68160 (4)

- `f7329db1` lfind.c:40 — Done, `MAX_OBD_NAME`.
- `528f1377` lfind.c:280 — Done for the first half: `argv[0]` is set to
  `progname` before `lfs_find_parse()`. Leaving the misplaced-operand wording
  alone — it is shared with `lfs find`, where "filename|dirname" is right.
- `3b301f5e` lfind.c:312 — Done, the two cases are separate messages and the
  bare DEVICE form is named.
- `0d87027e` lfind.c:352 — Done, documented under `--local`, including that
  it goes to stderr and only appears for more than one target.

## 68163 (5)

- `721b1edf` COMMIT_MSG:29 — Done, the message now says 165 was extended to
  ZFS and why the pool has to be exported.
- `c7396202` llapi_scan_device.3:371 — Done, both backends' vocabulary.
- `110c952a` lustre-build-zfs.m4:248 — Done, `${zfsinc}` dropped from the list.
- `396bd433` libscan_zfs.c:200 — You are right that the code is right and the
  comment is wrong; `zfs_set_prop_str()` writes `ldd_svname` through
  unchanged. Comment fixed. Done.
- `ee25ac8b` libscan_zfs.c:671 — Done, and the second half too: the bit is
  set for a successful lookup or ENOENT, so an unreadable spill block leaves
  it clear rather than claiming projid 0.

## 68288 (5)

- `eba25078` COMMIT_MSG:31 — Confirmed against `fld_handler.c:269` and
  `mdt_handler.c:8005`: another filesystem answers -ENOENT and is counted
  nameless. The paragraph now claims only the CAP_DAC_READ_SEARCH half and
  says what the wrong mount actually does. Done.
- `a3a3e45e` llapi_scan_rec_path.3:74 — Done, in the man page, the kernel-doc
  Return: block and the EXAMPLES fragment.
- `6d961f80` lfind.8:118 — Done, same correction.
- `755cf1b6` conf-sanity.sh:13091 — Right, it could not fire. Against
  `$got.raw` now. Done.
- `0c926782` liblustreapi_pfind.c:3066 — Done, the comment now says -EPERM
  and -ERANGE reach this arm and that another filesystem does not.

## 68413 (3)

- `d48b7a48` COMMIT_MSG:45 — Correct: the type test was the first clause of
  the `||`, so a name lookup behaved identically before and after. The
  paragraph now says the named user is coverage and only the `cf_user_id != 0`
  path changes. Done.
- `174839a6` mdd_changelog.c:60 — Done, `strncmp()` bounded by
  `sizeof(rec->cur_name)`.
- `11e13554` sanity.sh:22543 — Done, the test comment says the same.

## 68414 (2)

- `587d00d2` COMMIT_MSG:38 — Confirmed. `llapi_convert_str2mask()` seeds from
  `*oldmask` for a relative mask and `lfs_changelog()` seeds that with
  CHANGELOG_DEFMASK, so the disjoint case is reachable from the shell. The
  message says so now, and no longer claims `llapi_changelog_start_user()` is
  the only way in. Done.
- `139cf8f0` COMMIT_MSG:64 — Done. 160z now registers `-m creat` and reads
  back `--mask=-mark,-creat`, with the same user read without `--mask` as the
  control so an empty answer cannot pass for the fix working.

## 68415 (5)

- `e2fbfd68` llapi_scan_changelog.3:180 — Done, a `>0` entry in the man page
  and the kernel-doc corrected.
- `4beff86d` lustreapi.h:963 — Done, the structure has a kernel-doc block
  documenting `sc_size` and `sc_padding`, and the padding is now checked.
- `1724b037` liblustreapi_scan_changelog.c:275 — Real. A `bool glimpsed`
  tracks whether the second open succeeded; the strict bits are set only
  then, and `LLAPI_SCAN_LAZY_SIZE`/`LAZY_BLOCKS` otherwise. Done.
- `65e1417d` liblustreapi_scan_changelog.c:360 — Agreed the clock is the
  stream's. A wall-clock fallback needs a timeout on `chlg_read()`, which is
  a kernel-side change and not this patch's; documented instead — the man
  page now says the age is measured on the stream, what that means under
  FOLLOW and FOLLOW+CLEAR, and that a consumer needing a bound reads with
  FOLLOW clear and calls again.
- `c25cc66a` liblustreapi_scan_changelog.c:494 — No, it is not the same fact,
  and this was the worst of the round. `sr_event_uid`/`sr_event_gid` now
  carry the actor under `LLAPI_SCAN_EVENT_UID`, `sr_uid` is left for the
  owner a resolve supplies, and `-uid`/`-gid` are refused under `--changelog`
  without `--resolve` alongside `-size`. Done.

## 68416 (2)

- `bf3de3f1` liblustreapi_scan.c:710 — Done, `scan_param_padding_ok()` after
  the copy, as the siblings do.
- `1b8e4acd` liblustreapi_scan.c:772 — Done, the open moved below the filter;
  `sr_parent_fd` and `sr_fd` are -1 there, as `llapi_scan_changelog()` hands
  its own filter.

## 68417 (4)

- `8cec6f77` COMMIT_MSG:62 — Right, ONLY=56 exercises no `--since`. The line
  stays as the regression check on the shared paths and the message now says
  so, pointing at the tests patch for the new subtests — 160aa..160ad do not
  exist at this commit.
- `d0b38009` liblustreapi_pfind.c:3797 — Done, `checked_type` passed through.
- `3c110590` liblustreapi_pfind.c:3891 — Done. The caller's spelling of the
  root is kept beside the resolved one and put back on what is printed, so
  `lfs find . --since 2h` answers `./sub/f` again.
- `dc674e33` liblustreapi_pfind.c:3911 — Done, `llapi_search_mounts(rootbuf,
  ...)` for both branches, which fixes the symlink case and the `$MOUNT2`
  case together.

## 68418 (5)

- `460fd1aa` COMMIT_MSG:59 — Agreed; body rewritten to describe the final
  behaviour, and about half the length. Done.
- `9426a23d` liblustreapi_pfind.c:3085 — Right, the warning could never
  print. The FID-when-lost branch increments `fss_unresolved` as well as
  printing. Done.
- `bf268dc9` liblustreapi_pfind.c:3713 — Both halves real. A gone record is
  counted undecided where the search asks something only a lookup supplies,
  or names a subtree; and a `bool` in the state says whether the callback was
  reached, so an -ENOENT it returned is no longer read as the lookup's. The
  same flag closes it on the `--since` path too. Done.
- `4cd2a224` liblustreapi_pfind.c:3841 — Done, folded into the above: a
  subtree was named means undecided.
- `1f51ce44` liblustreapi_pfind.c:3942 — Done.

## 68419 (5)

- `a04d3600` COMMIT_MSG:78 — As on 68417: ONLY=56 stays as the regression
  check and the message says the new subtests are in the tests patch.
- `93da73db` lfs_find_parse.c:1266 — Done, `--since-cookie` and `--changelog`
  join `--since` in `find_device_supported()`'s refusal.
- `e0f007b7` liblustreapi_pfind.c:3724 — Done, the index goes through
  `strtoull()` with a leading sign refused, as the MDT number already was.
- `96321ade` liblustreapi_pfind.c:3911 — Done, the probe is
  `<cookie>.new`, which is what the write actually needs.
- `016ac5ee` liblustreapi_pfind.c:4726 — Real. `fss_path_rc` is folded into
  `rc` before the cookie is written, so a run that dropped matches leaves the
  anchors where they were. Done.

## 68420 (5)

- `764bdfc7` COMMIT_MSG:100 — Done, a third Test-Parameters line with
  `serverversion=2.15.6`.
- `5e10d407` lfs-find.1:789 — Both halves right, and the refusal message said
  the same non-existent names back to the user. It is `--mdt-count and
  --mdt-hash` now in the code, the man page moves them into the without-
  `--resolve` list and into the `--resolve` parenthesis. Done.
- `69c8d405` lfs-find.1:1080 — Done, broken with a literal `\e`.
- `5d3ab42c` sanity.sh:22643 — Right, the case was vacuous. `--mdt-hash
  fnv_1a_64` now, which reaches the refusal. Done.
- `8c5d6d1e` sanity.sh:22691 — Done, `stack_trap` beside the mkdir.
