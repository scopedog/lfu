# lreview, 2026-10-06: fix-1006 at bf7512ad90, 4 commits

Run 14:30-15:18, opus, one at a time: 68163 (27m, $11.21), 68415 (8m,
$3.95), 68417 (7m, $3.20), 68418 (7m, $3.61). 10 findings, all "low",
none in code this round changed. Skipped (comment/doc only): 68157 68159
68419 68420; pure carry: 69443.

## Fixed (fixup2 a2d6617d53, distributed by rebuild.py)
- 68163 #1: non-root caller, unreadable vdevs -> ENOENT; now -EACCES from
  lpc_error == LPC_EACCESS (2.2 and 2.4 both have it). Man3 -EACCES line.
- 68415 #1: a failed _CLEAR (e.g. unregistered sc_user) was logged and
  rc 0 returned; now the first failure is returned at the end, unless the
  callback stopped the scan. Man3 ERRORS paragraph.
- 68417 #3: "%llu objects were dropped with it" names nothing; 68418's
  wording moved down into 68417.
- 68417 #4: fss_root comment "and its depth" (no depth field).
- 68418 #2: message clause "-name 'lustre-MDT*' matched one" dropped; the
  FID gate drops a CL_MARK before -name is tested.
- 68418 #3: "Rule 2:" label with no rule list, dropped.

## Not done -- for the user
- 68163 #2: libscan_zfs.c is not compiled with libzpool's
  -DDEBUG -UNDEBUG -DZFS_DEBUG, so struct layouts with debug-only members
  (zfs_refcount_t, abd_t, dmu_buf_user_t) differ from libzpool's. Nothing
  reads a moved field today; a latent ABI trap. Build-system change.
- 68417 #1 (perf): the subtree test runs after llapi_scan_fid()'s full
  gather; could move into lfsp_filter.
- 68417 #2 (design): a time anchor older than the first surviving record
  (another user cleared) answers short with no warning.
- 68418 #1 (style): subject "lfs: add find --changelog and --resolve".
