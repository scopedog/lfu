# a1017 lreview -- the 10 changed commits, 10-17 14:04-15:22

Reports: ~/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_<sha>_*.md
(55f3579 0f535bd 63955f0 cf36f27 87a6262 4b9e433 acd528b c681fe6 a0737df eef7b94).
68415 and 68417 clean.  15 findings.

## FIXED (tx_lrv.py, pass 5)
- 68156 #1 + 68726: union initialiser need not zero buf's tail (GCC 15):
  memset, all three copies (device_test test6, scan_test test6, 68726 test13).
- 68158 #1: MY a1017 wording was wrong -- a zeroed fp_time_margin gives
  "+1y" a YEAR's margin (set_time() sets margin = unit), not none.
- 68158 #2/#3: message says why (the target front end) and which helpers
  change linkage.
- 68159 #1/#2: lfsp_got is left untouched -- my "leaves lfsp_got zero"
  was wrong; the man page listed it as overwritten too.
- 68159 #3: REGRESSION in 68159: -errno after
  llapi_layout_get_last_init_comp(), which returns the errno and sets none
  (walk path, lfs find -printf %Lc/%Li/%Lp/%LS error text).  Back to err.
- 68160 #1: the message still said test_300c skips on separate nodes.
- 68416 #1: llapi_scan_fid.3 says its opens are MDS opens, logged as
  OPEN/CLOSE when the mask has OPEN.

## DECLINED, lab-checked
- 68288 #2 (defect, medium) and #1: "llapi_root_path_open() of the client
  mount is an MDS open and hangs while MDT0000 is stopped".  ll_file_open()
  returns before any intent for is_root_inode() (llite/file.c:1125) --
  lreview's own 68416 run says so -- and on the VM, with no MDT mounted,
  open() of the mount root took 11 ms and lfs path2fid of it 3 ms
  (tests/lab-1017/08-rootopen.result.txt).

## HELD for the user (suggestions; no bug)
- 68159 #4: the undecided tally counts objects a later predicate would
  reject (--projid on an MDT without project ids + -size).  Matches are
  right; only the count is high.  Design change to find_decide().
- 68163 #1: --mdt/--ost/layout searches on ZFS import the pool twice (the
  target probe closes, scan_zfs_fini() evicts, the scan imports again).
  Performance follow-up.
- 68726 #1 (nit): sh_started can never be false at close.  Plus a coverage
  idea: an error after N records reaches the caller after N records.
- 68158: a sanity case for the interactive-shell pathstart fix.
