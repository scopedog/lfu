# a1018 lreview -- the 11 changed commits, 10-18 14:29-15:46

One at a time, full mode, opus, each commit in its own detached worktree of
~/lfs-fork-1014 (removed afterwards; branches untouched, nothing posted).
Reports: ~/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_<sha7>_*.md
Total **$36.04, 66.9M tokens, 76m52s** of review time.

| change | sha | cost / time | findings | verdict |
|---|---|---|---|---|
| 68156 | 4f2824972c | $5.03, 12m29s, 9.7M | 0 | clean |
| 68415 | 80f74c85f8 | $3.97, 7m29s, 7.9M | 2 | 1 nit (contract), 1 nit (msg) |
| 68416 | c052e2849b | $2.53, 4m19s, 3.9M | 1 | **real (doc), in this round's new text** |
| 68159 | 42e87c3edd | $4.85, 9m46s, 10.4M | 0 (+1 test suggestion) | clean |
| 68160 | 173609941f | $3.56, 9m45s, 7.4M | 0 | clean |
| 68163 | 70fe887ec9 | $4.45, 8m48s, 9.3M | 1 | nit (msg length) |
| 68288 | 97fe968464 | $3.79, 7m02s, 7.4M | 1 | nit (test), consequence overstated |
| 68419 | e7d922e474 | $2.76, 4m44s, 4.5M | 2 | 1 wrong on consequence (doc optional), 1 nit (man) |
| 69443 | 349200d1f3 | $1.28, 3m04s, 1.1M | 3 | **1 real (silent loss)**, 1 nit (inconsistency), 1 style |
| 69500 | d9cc93e608 | $1.99, 4m58s, 2.7M | 1 | nit (msg wrong) |
| 69729 | b933db95a4 | $1.83, 4m28s, 2.6M | 1 | nit (comment overstated) |

None of the findings repeats anything declined in a-1018/replies.md or the
earlier rounds (checked: CL_MARK, undecided, component tag, message
length, user_fid2path).  Nothing below has been applied.

---

## 68156 -- clean
No findings.

## 68415 -- 2 low

**(1) liblustreapi_scan_changelog.c:766 -- a CL_MARK carries the MDT name
in lfsr_name.**  NIT (contract).  Code is as described: `scan_cl_object()`
sends a CL_MARK (no FIDs, `scan_cl_rec_fids()` returns 0) to
`scan_cl_event()`; `scan_cl_absorb()` copies `changelog_rec_name()` whenever
`cr_namelen != 0`, and `mdd_changelog_write_header()` writes the obd name.
lustreapi.h:715/762 call lfsr_name "the basename within lfsr_path / NULL
where no name was recovered".  Consequence is narrower than stated: our own
consumer cannot be fooled -- `find_since_rec_cb()` drops CL_MARK and
FID-less records first (liblustreapi_pfind.c:6398-6415 at d9cc93e608).
Only a third-party llapi consumer matching on name alone would.
Fix: in `scan_cl_absorb()`, skip the name copy for `r->cr_type == CL_MARK`
(the pfid test two lines up already special-cases it), or say in
llapi_scan_changelog.3 that a mark's lfsr_name is the MDT's name.  Either is
one line; the man-page route keeps information a log reader may want.

**(2) /COMMIT_MSG:33 -- "a statx() per object" undercounts.**  NIT, true.
`scan_cl_mdt_stat()` does a second `statx(... AT_STATX_DONT_SYNC ...)`
(liblustreapi_scan_changelog.c:304) for the lazy size; the man page (372)
and the function comment (338) already say "a stat or two".  Fix: "one
O_PATH open by FID and a statx() or two per object".

## 68416 -- 1 low

**(1) llapi_scan_fid.3:246-253 -- the -EACCES entry added this round (#6)
is wrong twice.**  REAL (doc).  Verified:
- "A lfsp_want naming no field this call gathers opens nothing and is not
  affected" is false.  The type `statx(mnt_fd, at, AT_SYMLINK_NOFOLLOW,
  STATX_TYPE)` (liblustreapi_scan.c:896) runs for every call, whatever
  lfsp_want, and walks the path fid2path returned.  Under a 0700 directory
  the caller does not own it fails -EACCES.  (The code comment at :961 is
  about 0711, where search is allowed; that case is right.)
- "Only a caller without CAP_DAC_READ_SEARCH on -o user_fid2path" misses
  root squash: `ll_inode_permission()` (llite/file.c:6795-6813) swaps in the
  squash fsuid/fsgid and `cap_drop_fs_set()`s the effective set, so root
  passes `ll_fid2path()`'s capable() check and then fails the walk.
Fix (man only): "the object, or a directory on the way to it, could not be
searched or opened.  A caller without CAP_DAC_READ_SEARCH, or root on a
client with root squash, can meet this.  The FID lookup itself checks no
permission."  Drop the lfsp_want sentence.  The reply to
`1360e218_543e97db` (#6, drafted "Done. Documented...") stays true once the
text is corrected; fix before posting it.

## 68159 -- clean
No findings.  Suggestion: the walk-side behaviour changes (-btime/-newerbY
with no birth time no longer ending the walk, %Lc/%LS no longer printing
LLAPI_LAYOUT_DEFAULT, %Lo on an objectless component, %L*/--links on a
foreign dir) have no sanity case.  Checked: the stack's test diff covers
only `-printf '%Lc%Lh%Li%Lo'` on a directory (sanity, one case); none for
-btime, %LS or foreign.  Valid gap, held for the user.

## 68160 -- clean
No findings.

## 68163 -- 1 low

**(1) /COMMIT_MSG:125 -- message is ~140 lines and reads as replies to
earlier rounds.**  NIT, true: 169 lines at 70fe887ec9; "Neither exercises
the weak slot, and that is not an omission" (119), "Asking for ONLY=131d
here..." (126), the 131d/rwv aside (87).  Matches the Simple English
feedback (ablagodarenko 09-14).  Fix: trim to backend, EBUSY on an imported
pool, --search/lfsp_search, the --disable-shared weak link, conf-sanity 300;
the reasoning is already in Makefile.am / lustreapi_scan_backend.h.

## 68288 -- 1 low

**(1) conf-sanity.sh:14303 -- the --paths + --fid2path refusal check
passes on any non-zero exit.**  NIT; consequence overstated.  True that it
does not match the text, unlike the OST check just above.  But the
reviewer's example ($MOUNT not a mount on the MDS) cannot make it pass
wrongly: the refusal in `lfs_find_device()` (lfs.c:6646) is a pure argument
check before anything is opened.  Pre-existing in PS31 (9cfddeaaf3), not
new this round.  Fix: capture the output and `grep -q "two ways to name an
object"`, as the OST arm does.

## 68419 -- 2 low

**(1) liblustreapi_pfind.c:6872 -- an undecided object does not hold the
cookie anchors.**  WRONG on the consequence; the code is as described.
Under --since-cookie (no --changelog), the only undecided route is
`find_rec_layout()` returning 1, which means the object's layout bytes did
not parse (unknown magic, torn composite, byte-swapped SEL, comment at
:4495).  That is the object's state, not a transient: a `--since <time>`
rerun over the same window is undecided on it again, so holding the anchor
would gain nothing and would pin the cookie forever (the reviewer concedes
the --changelog analogue).  A layout change that fixes it writes a new
CL_LAYOUT record, which the next run sees.  Optional: one sentence in
lfs-find.1 / llapi_find_since.3 that undecided objects are reported in the
warning and do not hold FILE.  Decline or doc-only.

**(2) llapi_find_since.3:204 -- ERRORS misses two cookie -EINVAL cases.**
NIT, true: `find_cookie_check()` refuses an empty fp_since_cookie
("--since-cookie needs the name of a file"), and `find_cookie_read()` a
header with no search root ("names no search root in its header"); the
page lists neither.  Fix: add "an empty cookie name" and "a header that
names no search root" to the -EINVAL list.

## 69443 -- 3 low

**(2) liblustreapi_pfind.c:6870 -- an MDT anchored at 0 is never
re-checked, so a purge during the run is silent.**  REAL (silent loss, the
exact class this commit exists to close).  Verified at 349200d1f3 and still
so at 69500 (d9cc93e608): the per-MDT recheck requires
`starts[mdts[i]] != 0`; `find_cookie_was_empty()` reads the oldest record
but throws it away; `find_since_gap()` (69500) returns at once when
fp_since_cookie is set.  Sequence: MDT0001 recorded 0; pre-pass sees
oldest 1 (no warning); while MDT0000 prints, another user clears MDT0001
through 500; its scan starts at 501, rc 0, cookie advances; 1..500 are
gone.  Not in lfs-find.1's "Not caught" list (822-826).
Fix: let `find_cookie_was_empty()` return the oldest it saw (into a
per-MDT array, or reuse `reached[]`), and in the loop recheck an anchor-0
MDT with `find_cookie_purged(mdtname, oldest_seen - 1, ...)` when
`oldest_seen != 0`.  That refuses when the log moved past what the pre-pass
saw, and covers the warned case (oldest > 1) too.  An empty log at the
pre-pass (oldest 0) stays uncatchable; add that one to "Not caught".
Needs a DNE lab arm against the unfixed build.

**(3) liblustreapi_pfind.c:6875 -- any error from find_cookie_purged()
ends the run; a scan read failure goes on to the next MDT.**  NIT, true
(inconsistency, no wrong answer: the cookie is not rewritten either way,
only the later MDTs' matches go unprinted).  Fix: break only on -ESTALE;
route other errors through the scan-failure handler (record in
fss_scan_rc, continue unless fp_stop_on_error).  Pairs with 69500 (1).

**(1) /COMMIT_MSG:7 -- tag "lfs:", summary not imperative.**  STYLE.  True
that the diff is liblustreapi + man pages only, but 68419 and 69500 use
"lfs:" the same way for user-visible find features; the series is
consistent.  Decline, or retag all three together if wanted.

## 69500 -- 1 low

**(1) /COMMIT_MSG:40 -- "the run stops as it does when the scan itself
fails" is wrong.**  NIT, true: a find_since_gap() error goes to the scan
failure handler, which breaks only on fp_stop_on_error; lfs find never sets
it (the only setter is liblustreapi.c:3486, not on this path).  The MDT is
skipped, the rest are scanned, the run fails at the end.  Fix: "that MDT is
not scanned, and the run fails at the end, as when the scan itself fails."
If 69443 (3) is fixed, this sentence also describes the recheck.

## 69729 -- 1 low

**(1) liblustreapi_pfind.c:4632 -- "it has no directory with a linkea" is
not true after LFSCK.**  NIT, true, and the comment is new in this commit
(blame b933db95a4).  `lfsck_create_lpf_remote()` (lfsck_lib.c:814-846)
creates .lustre/lost+found/MDT000N on that MDT with a linkea naming its
parent, so the dirmap can map it and dm_used is 1.  The point of the
comment (test the built flag, not dm_used) still holds.  Fix: "usually has
none (lost+found/MDT000N, once LFSCK made it, is the exception)".

---

## Fix list, in priority order (none applied)
1. 69443 (2): recheck anchor-0 MDTs against the oldest the pre-pass saw;
   lab-prove against the unfixed build.  Real silent loss.
2. 68416 (1): correct the -EACCES text added this round, before posting
   the #6 reply.
3. 69443 (3) + 69500 (1): one behaviour for a failed oldest-record read,
   and a message that says it.
4. Nits: 68415 (1)(2), 68419 (2), 68288 (1), 68163 (1), 69729 (1).
5. Decline: 68419 (1) (or one doc sentence), 69443 (1).
6. Held for the user: 68159 test-coverage suggestion.

---

# re-lreview, 10-18 late (after pass d)

One at a time, full mode, opus. Each commit had its own detached worktree under
scratchpad/lrv3/, removed afterwards. Nothing posted, nothing applied.
Reports are in ~/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_<sha7>_*.md.
Total $5.77, 8.1M tokens, 15m48s.

| change | sha | cost / time | findings | verdict |
|---|---|---|---|---|
| 69443 | df82f49a83 | $1.56, 3m58s, 1.8M | 1 | nit, true |
| 69500 | 26f7c0b1f6 | $2.06, 5m44s, 3.2M | 1 | nit, true; decline (states intent) |
| 69729 | 8c31e38c34 | $2.15, 6m06s, 3.1M | 2 | 1 known and documented (follow-up?), 1 nit, true |

No finding on the pass-d change itself (warn and advance) beyond the
message wording.

## 69443 -- 1 low

**(1) liblustreapi_pfind.c:5416 -- the new warning names only `seen`.**
NIT, true. `find_cookie_recheck()` prints `seen` but not the `oldest` that
find_cl_first() just returned. find_cookie_purged()'s -ESTALE message names
both. Fix if wanted: add "and now starts at %llu" (or "is now empty" when
oldest is 0). Lab wording today: "'lfst-MDT0001' started at 1 when the
search began and has been purged since: ...". Note: oldest < seen is
possible after a log restart, so "[seen, oldest) is missing" is not always
the range. The message should name the two numbers, not a range.

## 69500 -- 1 low

**(1) liblustreapi_pfind.c:5373 -- the `fp_since_cookie != NULL` test in
find_since_gap() can never be the one that returns.** True:
llapi_find_since() refuses a cookie together with --since (:6683), and an
unknown kind (:6660), so a cookie always arrives with LLAPI_SINCE_NONE and
the kind test returns first. Harmless. The explicit test says that the cookie
keeps its own check, which the commit message also says ("The cookie keeps
its own check and is skipped here"). Decline, or simplify to `kind ==
LLAPI_SINCE_NONE` if the user prefers.

## 69729 -- 2 low

**(1) liblustreapi_pfind.c:3623 -- an IGIF root is not printed without
--internal, where an LU_ROOT_FID root is.** True, and known: the commit
message says so ("Without --internal an IGIF root is not printed: it has no
linkea, so the scan counts it as internal"). Checked in
liblustreapi_scan_device.c:222-226: fid_is_root() makes LU_ROOT_FID
VISIBLE, while an IGIF without a link is INTERNAL for an MDT. Classifying
happens per object, before the dirmap knows .lustre's parent, so a fix
means classifying later (or treating .lustre's parent as visible after the
pre-pass). Not this round. Held for the user as a possible follow-up.

**(2) liblustreapi_scan_device.c:1646 -- "an IGIF root on a filesystem
upgraded from before 2.4" sits on a loop that serves every filesystem.**
NIT, true. It was added in this commit (it replaces the literal
LU_ROOT_FID). `scan_dirmap_root()` returns .lustre's parent, which is
LU_ROOT_FID unless the filesystem predates 2.4. Fix: "/* .lustre's parent:
an IGIF on a filesystem from before 2.4 */".

---

# re-lreview, 10-18 evening (after pass f)

One at a time, full mode, opus. Detached worktrees under scratchpad/lrv4/,
removed afterwards. Nothing posted, nothing applied. Reports in
~/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_<sha7>_*.md.

| change | sha | cost / time | findings | verdict |
|---|---|---|---|---|
| 69700 | dfa074ae7d | $2.51, 5m13s, 4.0M | 1 | true, unlikely flake, in a test this round did not touch |
| 69443 | 1340232dfb | $1.56, 3m30s, 1.9M | 3 (one point, three places) | nit, true |
| 69729 | d102567272 | -- | NOT REVIEWED | user paused lreview (credits); the run was killed after 74s, no report. Do not retry until the user says so |

69729 still owes an lreview of pass f: the comment nit and the new IGIF-root
sentences in llapi_find_device.3 and lfs-find.1.

No finding on #1 (rate slot for a pre-filter skip) or #2 (the warning names
both numbers) themselves.

## 69700 -- 1 low

**(1) llapi_scan_test.c:1033 -- test19's `calls == 3` can see a 4th call on a
slow node.** True in principle. llapi_scan_cb_init() checks ss_stop_rc after
the rate wait, but the stopper sets it only after scan_rec_gather() (default
lfsp_want: LMV ioctl, get_lmd_info_fd(), so MDT RPCs) and the consumer
return. If those take more than one 200 ms interval, the thread holding the
next slot wakes, finds ss_stop_rc still 0 and delivers. This needs local RPCs
taking over 200 ms, so it is unlikely. It is test code from PS1, not from #1.
Fix if wanted: `.lfsp_want = LLAPI_SCAN_TYPE` in that sp, so nothing is
gathered between the wake and the consumer call. Held for the user.

## 69443 -- 3 low (one point)

**(1)(2)(3) lfs-find.1:828, llapi_find_since.3:288, /COMMIT_MSG:40 -- "records
made and purged during the run on an MDT whose log was empty when it began" is
broader than the code.** NIT, true. find_cookie_recheck() returns early only
for `anchor == 0 && seen == 0`. An MDT anchored past 0 whose log was empty
goes through find_cookie_purged(), so new records purged during the run are
refused when the oldest left is past anchor + 1. If the purge empties the log
again, it is not caught, but the existing "a purge that empties the log of an
MDT recorded past 0" clause already says so. The wording predates pass f.
Fix: "on an MDT recorded at 0 whose log was empty when it began" (and
"anchored at 0" in the man3 page), in all three places.
