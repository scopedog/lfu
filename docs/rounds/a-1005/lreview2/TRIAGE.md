# lreview (2), 2026-10-05: the fix-1005 tip, 7 changed commits

Run 13:54-14:32, opus, one at a time. 68288 skipped (docs-only: man `\c`,
comment); 68156 already re-reviewed after its csum fix; 68158 parent only.
20 findings. Checked against ~/lfs-fix-1005 at ae9b2ca3a3.

## Real defects, confirmed in the tree
- 68417 #1: _ONCE's FID set is per llapi_scan_changelog() call, one call per
  MDT -> on DNE an object in two MDTs' logs is looked up and printed twice.
  Needs a cross-MDT seen-set in find_since_state. DNE lab to prove.
- 68415 #2: sl_accepted assigned, not raised -> under COALESCE|CLEAR a
  held object flushed after a busy-limit delivery moves it back; final
  clear stops short, record redelivered next run. Fix: max().
- 68159 #1: find_device_targets() returns 1 on a non-matching --mdt/--ost
  before the kind refusals -> same impossible search is 0/empty on one
  device, -ENOTSUP on another. Fix: all kind checks first.
- 68418 #1: --changelog refuses fp_max_depth != -1, so a calloc'd
  find_param (0) gets -ENOTSUP naming --maxdepth; the device path accepts 0.

## Real, minor / wording
- 68417 #2: own fileset test misses the IGIF exception; use
  find_mount_is_fileset().
- 68419 #3: cookie header without " under <root>" still accepted.
- 68420 #1/#2 (and the 68419 comment): "-MDT-1 ... out-of-bounds write" is
  false, `mdt >= nstarts` already drops it. Reword.
- 68415 #1: commit message, glimpse/times wording.
- 68416 #2: "relative to the filesystem root" -> mount root (man + comment).
- 68416 #1: V1-getinfo-only modules -> every lookup -ESTALE. Doc the case.
- 68418 #4: two -ENOTSUP entries in llapi_find_since.3; name fp_ fields.

## Design, for the user
- 68419 #1: changelog writers set the llog bitmap bit after the write and
  out of order (mdd_dir.c:832-835 drops lgh_lock before dt_record_write),
  so a run reaching the tail can see N+1 before N; the max-index anchor
  then skips N for good. Verified in the kernel. Fix or document?
- 68418 #2: --changelog on a fileset mount lists the whole fs; outside
  objects print as FIDs, look deleted, no warning. Refuse, warn, or doc?
- 68419 #2: cookie inside the searched tree reports itself every run.
  Skip own FID, or doc?
- 68419 #5: document the cookie format / per-MDT line removal (suggestion).

## Style, skipped (user 10-05 rule)
68417 #3 (already skipped once), 68415 #3, 68418 #3, 68419 #4.
