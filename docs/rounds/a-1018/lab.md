# Round a-1018 lab: #21 (68419 empty-MDT cookie) and #15 (upstream --foreign)

VM rhel9.7-server-mgs-mds-clone (192.168.122.10), loaded modules
`2.17.58_65_g8618869`, FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2, REFORMAT per stage
(/tmp/lfst-* only). Scripts and raw output: `tests/lab-1018/`
(`01-build.sh` .. `05-all.sh`, `01-build.result.txt`, `05-all.result.txt`).
VM started 14:30, shut down 14:44.

## Arms (built 14:32-14:34, userspace only, git archive -> /tmp/lab1018-<arm>)

| arm | commit | liblustreapi md5 | "was empty when" in lib |
|---|---|---|---|
| o  | b1018-fork-1014 f9034db8d7 (before #21) | c2158f09c4 | 0 |
| n  | fork-1014 d9cc93e608 (68419 = e7d922e474) | 2fc85d6309 | 1 |
| m  | master-1014 ee61b3f6dd (stock) | 36f670ffc0 | 0 |
| mf | m + #15 fix 6ea0abfcd9 | d0eb5540bd | 0 |

Each arm's `lfs` has RPATH `/tmp/arm1018<arm>/lib` (copy of its own build,
md5 equal). Loaded library proven per run by `LD_TRACE_LOADED_OBJECTS` and by
`/proc/<pid>/maps` of a live `lfs` (bound over /usr/bin/lfs for the run).

## #21 A/B: sanity 160Ac (new sanity.sh in both arms)

14:34:25 lib=o: maps `/tmp/arm1018o/lib/liblustreapi.so.1.0.0`
    FAIL 160Ac (11s)
    sanity: FAIL: test_160Ac an empty log left no line: # lfs find --since-cookie for lfst under /mnt/lfst/d160Ac.sanity
14:35:50 lib=n: maps `/tmp/arm1018n/lib/liblustreapi.so.1.0.0`
    PASS 160Ac (14s)

## #21 by hand (14:37:30, one fixture, both arms)

One changelog user (cl1 on each MDT, the "other" consumer); lfs find
registers none. Log cleared to 0 records on both MDTs, then run 1:

    cookie o: header only (no MDT lines)
    cookie n: lfst-MDT0000 0 / lfst-MDT0001 0

Then touch lost1..5 (MDT0000 log 10 recs), cl1 clears them all, touch kept
(log starts at 14). Run 2:

    run2 o rc=0
         /mnt/lfst/ck/kept                    <- lost1..5 gone, nothing said
       cookie after: lfst-MDT0000 15;
    run2 n rc=0
         lfs find: 'lfst-MDT0000' starts at 14 and was empty when '.../ck2.n' was written: any records purged since then are not in the answer
         /mnt/lfst/ck/kept
       cookie after: lfst-MDT0000 15;lfst-MDT0001 0;

Warn-and-continue as decided (rc 0, records after the purge returned). The
idle MDT0001 (still empty, oldest 0) gives no warning and keeps its 0 line.

## #21 regression: 160A* on n (14:38:41)

    PASS 160Aa 160Ab 160Ac 160Ad 160Ae 160Af   (6/6, 0 FAIL, 0 SKIP)

160Ac carries 68419's tests; 69443 (349200d1f3) adds none; 160Af comes from 69500 (d9cc93e608).

## #15: lfs find --foreign on a walk (14:40:45, one fixture, alternated x2)

Fixture under /mnt/lfst/fr (MDT0): fdir (`lfs mkdir --foreign=none
--xattr`), ffile (`lfs setstripe --foreign=none`), sdir (`lfs mkdir -c 2`),
dir, file, sdir/f. enable_foreign_dir=1. Both runs identical:

| query | m (stock master) | mf (fixed) |
|---|---|---|
| `--foreign` | ffile sdir | fdir ffile |
| `! --foreign` | . dir fdir file sdir/f | . dir file sdir sdir/f |
| `--foreign -type d` | sdir | fdir |
| `! --foreign -type d` | . dir fdir | . dir sdir |
| `--foreign=none -type d` | sdir | fdir |
| `--foreign=symlink` | (none) | (none) |

Stock is wrong for exactly the two directories with an LMV (fdir, sdir);
plain dir and both files are right in both arms. Confirms the code read.

## #15: sanity 27K 27Ke 27Kf (mf's sanity.sh)

14:41:40 lib=m:  PASS 27K, 27Ke; FAIL 27Kf "--foreign found '.../ffile .../sdir'"
14:42:51 lib=mf: PASS 27K, 27Ke, 27Kf

Patch: `docs/rounds/a-1018/foreign/0001-LU-XXXXX-utils-fix-lfs-find-foreign-on-directories.patch`
(worktree ~/lfs-foreign-1018, branch lu-foreign-dir, on master-1014;
checkpatch 0/0). Ticket draft: `foreign/ticket.txt`. Not filed, not pushed.

## Notes

- The commit-msg hook refuses `LU-XXXXX`; committed with --no-verify. Put the
  real ticket number in before any push.
- checkpatch wants a 12-char Fixes hash: `Fixes: baba1fd07a97 (...)`.
- 68159's `not_foreign` workaround was not re-checked against the fix; that
  is the next step once the fix is under the series.

---

# 10-18 pm: lreview fix #1 (69443, anchor-0 recheck), A/B (appended 16:13)

Rewrite: tx_b.py + tx_c.py through forktx3.py (logs forktx_b.log,
forktx_c.log); old tips tagged c1018-<branch>. Arms on the same VM, same
recipe (01-build.sh), userspace only:

| arm | commit | liblustreapi md5 | "when the search began" in lib |
|---|---|---|---|
| n | c1018-fork-1014 d9cc93e608 (unfixed; this morning's n build, md5 rechecked) | 2fc85d6309 | 0 |
| f | fork-1014 2794517e21 (fixed) | 956b36bd31 | 1 |

VM started 15:59, shut down 16:12. Script `tests/lab-1018/06-recheck0.sh`,
driver `07-all.sh`, raw output `07-all.result.txt`. REFORMAT per arm run,
order n f f n.

## How the timing was forced

Not raced. lfs writes into a FIFO; the script reads one line and stops
reading. 4000 MDT0000 matches (~190 KB) fill the pipe, so lfs blocks in
write() while still inside MDT0000's scan. Before the clear, every run
logged: wchan `pipe_write`, the only changelog fd open is
`changelog-lfst-MDT0000`, and a gdb backtrace
`write <- llapi_printf <- find_decide <- find_since_rec_cb <- llapi_scan_fid
<- find_since_cand_cb <- scan_cl_deliver` (liblustreapi_scan_changelog.c).
Then the other changelog user (cl1, the only one) clears MDT0001, and the
FIFO is drained. The blocked process's /proc/<pid>/maps names the arm's
library in every run.

Fixture per pass: directories made before cl1 registered (so unlogged), logs
cleared to 0 records, run1 writes `MDT0000 0; MDT0001 0` (asserted), then
4000 creates on MDT0000 and lost1..5 on MDT0001 (10 records), run2 (the
blocked one), run3 (the next run).
- A: MDT0001's log starts at 1 (never used), clear then `touch kept`.
- B: same mount, second pass: MDT0001 starts at 13, clear empties it.

## Results (identical in both runs of each arm)

| | n (unfixed) | f (fixed) |
|---|---|---|
| A run2 | rc 0, 4000 big + kept, **no message at all**, cookie -> `MDT0000 8000; MDT0001 12` | rc 116 (ESTALE): "'lfst-MDT0001' started at 1 when the search began and was purged before it was read ...", cookie left `0; 0` |
| A run3 | rc 0, 0 lines: lost1..5 gone for good, never said | rc 0, 4000 big again + kept, warns "'lfst-MDT0001' starts at 11 and was empty when ... written", cookie `8000; 12` |
| B run2 | rc 0, only the pre-pass warning "MDT0001 starts at 13 and was empty ..." (about records before 13, the ones lost here were in the log at that check), cookie -> `16000; 0` | rc 116: same pre-pass warning, then "'lfst-MDT0001' started at 13 when the search began and was purged before it was read", cookie left `0; 0` |
| B run3 | rc 0, nothing | rc 0, 4000 big again, warning for MDT0000 only: MDT0001's log is now empty, so the next run cannot see the loss (already reported by run2) |

A on the unfixed library is the lreview case exactly: rc 0, a short answer,
the cookie moved past the loss, nothing said. B is the emptied-log case that
`find_cookie_purged(mdt, oldest_seen - 1)` alone would have missed (an empty
log is never "past"); the fix tests "oldest changed" instead.

Not exercised: the read-error path (#3). It is a code-read change only.

## 160A* on f (16:10)

    PASS 160Aa 160Ab 160Ac 160Ad 160Ae 160Af   (6/6, 0 FAIL, 0 SKIP)

---

# 10-18 late: pass d (user decision: anchor-0 recheck warns, rc 0), appended 16:35

Rewrite: tx_d.py (+ tx_e.py, a comment shortened to 80 columns) through
forktx3.py (logs forktx_d.log, forktx_e.log); old tips tagged d1018-<branch>.
Only fork-1014 moved (69443 1f843bef66 -> df82f49a83, 69500 2794517e21 ->
26f7c0b1f6); no other branch descends from 69443.

Cookie choice: for an MDT recorded at 0 whose oldest record moved before it
is read, warn (names the MDT) and let the cookie advance as usual. That is
what find_cookie_was_empty()'s warning already does. The records are gone
from the log, so holding the cookie back recovers none of them and only makes
the next run repeat this one. The next run starts after what this run read,
so it is not silently wrong. The loss is reported once, by the only run that
can see it.

Arm g = fork-1014 26f7c0b1f6, built 16:27 by 01-build.sh, liblustreapi md5
fa79f7cb96 ("has been purged since" 1, old refusal text "was purged before
it was read" 0). VM started 16:26, shut down 16:32. Driver `08-all.sh`, raw
`08-all.result.txt`; 06-recheck0.sh unchanged except that it also counts the
new string. Run twice (g1 16:27, g2 16:29), identical. Every blocked run:
wchan pipe_write, only fd changelog-lfst-MDT0000, same gdb stack as f, maps
`/tmp/arm1018g/lib/liblustreapi.so.1.0.0`.

| | f (pass b/c, refused) | g (pass d) |
|---|---|---|
| A run2 | rc 116, cookie left `0; 0` | **rc 0**, 4000 big + kept, warns "'lfst-MDT0001' started at 1 when the search began and has been purged since: records purged during the run may be missing from the answer", cookie -> `8000; 12` |
| A run3 | rc 0, 4000 big again + kept, warning | rc 0, 0 lines, no message, cookie `8000; 12` |
| B run2 | rc 116, cookie `0; 0` | **rc 0**, 4000 big; pre-pass warnings (MDT0000 starts at 8001, MDT0001 starts at 13), then "'lfst-MDT0001' started at 13 when the search began and has been purged since: ...", cookie -> `16000; 0` |
| B run3 | rc 0, 4000 big again | rc 0, 0 lines, no message |

So the loss (lost1..5) is warned of in the run where it happens, and the next
run neither repeats the answer nor goes silent about a loss it could still
see. Same answer as the unfixed n arm, plus the warning n never gave.

## 160A* on g (16:30)

    PASS 160Aa 160Ab 160Ac 160Ad 160Ae 160Af   (6/6, 0 FAIL, 0 SKIP)

loaded modules `2.17.58_65_g8618869`; lfs maps /tmp/arm1018g/lib.

---

# 10-18 evening: pass f (#1 69700 rate slot for pre-filter skips, #2 69443 warning names both numbers), appended 17:00

Rewrite: tx_f1.py (start 69700), tx_f2.py (start 69443), tx_f3.py and
tx_f4.py (69729) through forktx3.py (log forktx_f.log); old tips tagged
e1018-<branch>. 69729 needs no lab (a comment and man pages).

Arms, built 16:51-16:52 by 01-build.sh (result 09-build.result.txt):

| arm | commit | liblustreapi md5 |
|---|---|---|
| r0 | e1018-rate-1017 4d35b0b1b0 (69700 before #1) | c9b26d77c2 |
| r1 | rate-1017 dfa074ae7d (69700 with #1) | 2fa87b9cc2 |
| h  | fork-1014 de3b3921a0 (69443 1340232dfb + 69500) | 475e6cac2be |

VM started 16:50, shut down 16:57.

## #1: llapi_scan_device_test test0+test7 on a torn MDT image (10-t7.sh, raw 10-t7.result.txt)

A torn inode CAN be made: llmount (MDSCOUNT=1), 3000 files by createmany -m,
unmount, copy /tmp/lfst-mdt1 twice. On one copy debugfs `sif <ino> mode
0170644` on 2000 of the files' inodes: an invalid file type, checksum
rewritten, bitmap still in use. So the inode reads fine, and only
scan_inode_plausible() refuses it: LLAPI_SCAN_SKIP_INVALID, before the
pre-filter. e2fsck -fn on the torn copy rc 4. Every run's strace shows its own
arm's liblustreapi.so.1 and /tmp/arm1018<arm>/lib/lustre/scan_osd_ldiskfs.so.

| | clean copy | torn copy (2000 of 3261 seen are SKIP_INVALID) |
|---|---|---|
| r0 pass 1 | test0 pass, test7 pass | test0 pass, **test7 FAIL**: "3261 objects at 6522/s took 0.198s, at least 0.500s expected" |
| r1 pass 1 | pass, pass | pass, **pass** |
| r0 pass 2 | pass, pass | pass, **FAIL** (0.198s again) |
| r1 pass 2 | pass, pass | pass, pass |

0.198 s is (3261 - 2000) / 6522 = 0.193 s plus overhead: before the fix the
2000 skipped objects were in ss_seen but took no slot, as the AI comment
said. test0 (seen = filtered + skipped + classified) passes on both, so the
accounting did not change.

## #2: the anchor-0 recheck warning (11-all.sh, raw 11-all.result.txt)

06-recheck0.sh on h, once (16:53):
- A run2 rc 0, 4000 big + kept, cookie -> `8000; 12`: "'lfst-MDT0001' started
  at 1 when the search began and has been purged since, and now starts at 11:
  records purged during the run may be missing from the answer"
- B run2 rc 0, 4000 big, cookie -> `16000; 0`: the two pre-pass warnings, then
  "'lfst-MDT0001' started at 13 when the search began and has been purged
  since, and is now empty: records purged during the run may be missing from
  the answer"
- run3 in both: rc 0, 0 lines, no message. Same behaviour as g; only the words changed.

## 160A* on h (16:55)

    PASS 160Aa 160Ab 160Ac 160Ad 160Ae 160Af   (6/6, 0 FAIL, 0 SKIP)

loaded modules `2.17.58_65_g8618869`; lfs maps /tmp/arm1018h/lib.
