# HEAD — LU-20650 lfs: find --since-cookie, check each MDT when read

- **Commit:** `ac9947b96da1` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 4 finding(s), severity **high**
- **Run:** opus, 2.2M tokens, $1.60, 3m30s

## Overall assessment

Problematic, see inline comments. The new check reads the coalesced stream, and it refuses ordinary incremental runs. The 160Ac test sets the changelog mask to `creat`, which gives one record per file, so it cannot show this. A second-run case with the default mask (e.g. `echo x > b`, which logs CREAT and then CLOSE) would.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 5961)

(defect) find_since_filter_cb() is not called once per changelog record. llapi_find_since() always sets LLAPI_SCAN_CL_F_COALESCE, and with it sc_filter runs from scan_cl_deliver(), once per coalesced object, when scan_cl_flush() lets that object go. The record it gets is built by scan_cl_rec_event(), and its lfsr_event_index is co_index, the index of the object's *latest* event (scan_cl_absorb() moves co_index on every record).

So fss_first is not the first index read. Take a cookie at A, followed by a file created and written:

    A+1  CREAT  f
    A+2  CLOSE  f   (CL_CLOSE is in CHANGELOG_DEFMASK)

Both records coalesce into one object, which is delivered with index A+2. fss_first = A+2 > A+1, so the run fails with -ESTALE. The message says records were purged, but nothing was. The same happens whenever the first object flushed is not the one at A+1: objects flush in last-seen order, and a CL_MARK is delivered at once through scan_cl_event().

The cookie is not rewritten, so every later run re-reads the same records and is refused the same way. --since-cookie stays stuck until the cookie file is deleted.

Would it be simpler to repeat find_cl_first(mdtname, 0, &oldest) just before each MDT's llapi_scan_changelog(), and keep the `oldest > anchor + 1` test? That reads one record and does not depend on what the stream delivers.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 6520)

(defect) Can cr_index really have no gaps on one MDT? In the changelog branch of llog_osd_write_rec() (mdd_dir.c), cr_index = ++mc_index is assigned under lgh_lock. The lock is then dropped "for parallel writes", and the llog bitmap bit is set only after dt_record_write() succeeds. llog_process_thread() skips any index whose bit is clear (llog_is_index_skipable()).

So with two writers at the tail, A+1 can still be in flight while A+2 is already marked. The reader then delivers A+2 first, and this check reports a purge that did not happen. This is the same race the man page says is not covered, but here it shows up as a false -ESTALE.

The write-failure path in that same function returns without giving back the index it took. That leaves a permanent hole at A+1, and every run from that cookie would then be refused.

### 3. `Documentation/man1/lfs-find.1` (line 785)

(minor) "Refused then" holds only if the later MDT still has a record after the anchor. Suppose a clear during the earlier MDT's read empties that log past the anchor. Then the scan delivers nothing and fss_first stays 0, so the check is skipped and the cookie is rewritten with the same anchor. The loss is refused only on a later run, once new records arrive (find_cookie_check() then sees oldest > anchor + 1). Worth saying, if the text is refreshed.

### 4. `/COMMIT_MSG` (line 16)

"The filter callback already sees every record in order" is not true for this caller. With LLAPI_SCAN_CL_F_COALESCE, sc_filter sees one coalesced record per object, carrying that object's latest index, in flush order. "Indexes on one MDT have no gaps" on the line above also does not hold for records still being written at the tail (see the inline comment).
