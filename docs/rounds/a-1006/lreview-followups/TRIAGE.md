# lreview on the three follow-ups, 2026-10-06 17:47-17:55 (opus)

gap bc5e232bd9 4 / pick 0a175c4191 2 / zfsflags bb7e771b7f 1, all low.
All 7 fixed (now ceaeec5973 / 0f750eed55 / d7bc5decf4):
- gap #1 (real): the TIME warning claimed a loss it cannot prove (cleared
  records may all predate the window). Time wording now says only where
  the log starts; INDEX keeps "cleared past ... not in the answer"
  (exact). Man1/man3 say which is certain. 160Af greps "has been cleared".
- gap #2: log read even with no anchor (--changelog all, --since 0);
  kind checked first now.
- gap #3: struct moved above find_cl_first_cb()'s comment; @first_time
  documented.
- gap #4: message names find_since_gap()/find_cl_first(), not "69443".
- pick #1: message says the gone/dropped counts and exit status can
  differ (objects outside the subtree are no longer gathered).
- pick #2: fss_pre_fid cleared after llapi_scan_fid(). The cleaner fix
  (llapi_scan_fid() sets lfsr_fid before the filter) needs a 68416 respin
  -- offered to the user, not done.
- zfsflags #1: message history: 2.0/2.1 Makefile.am, 2.2 FORCEDEBUG,
  2.3 LIBZPOOL_CPPFLAGS + comment (verified in the tags); zstream dropped.
