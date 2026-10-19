# a1018 lreview fixes (second pass, applied with forktx3.py from 68415 up):
# 69443 (2): an MDT recorded at 0 was never rechecked during the run.
#   find_cookie_was_empty() now keeps the oldest record it saw (seen[]),
#   find_cookie_recheck() refuses if that moved before the MDT is read.
# 69443 (3) / 69500 (1): a failed read of the oldest record before an MDT is
#   a failed scan (skip it, fail at the end), not the end of the run.
# 68416 (1): the -EACCES entry of llapi_scan_fid.3.
# 68415 (1)(2), 68419 (2), 69729 (1): nits.
import sys
PF = 'lustre/utils/liblustreapi_pfind.c'
LF = 'Documentation/man1/lfs-find.1'
FS = 'Documentation/man3/llapi_find_since.3'
SF = 'Documentation/man3/llapi_scan_fid.3'
SC = 'Documentation/man3/llapi_scan_changelog.3'
HITS = {}

RECHECK = """/*
 * Just before an MDT is read: did a purge reach it after find_cookie_check()?
 * An anchored MDT is tested as there.  One recorded at 0 had nothing
 * consumed, so any move of its oldest record from @seen, an emptied log
 * included, lost records.  One that was empty then (@seen 0) cannot be told.
 *
 * Return: 0, -ESTALE (said here), or the errno reading the log.
 */
static int find_cookie_recheck(const char *mdtname, __u64 anchor, __u64 seen,
			       const char *cookie)
{
	__u64 oldest;
	int rc;

	if (anchor == FIND_COOKIE_NONE || (anchor == 0 && seen == 0))
		return 0;
	if (anchor != 0)
		return find_cookie_purged(mdtname, anchor, cookie, NULL);

	rc = find_cl_first(mdtname, 0, &oldest);
	if (rc < 0 || oldest == seen)
		return rc;
	llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ESTALE,
		    "'%s' started at %llu when the search began and was purged before it was read: those records are not in the answer; '%s' is left where it was",
		    mdtname, (unsigned long long)seen, cookie);
	return -ESTALE;
}

"""

R = {
PF: [
# --- 69443 (2)(3): find_cookie_purged() leaves a read error to its caller
('purged-doc', """ * Return: 0, -ESTALE (said here), or the errno reading the log.  @oldest,
 * if not NULL, is 0 for an empty log.
 */""", """ * Return: 0, -ESTALE (said here), or the errno reading the log, which the
 * caller reports.  @oldest, if not NULL, is 0 for an empty log.
 */"""),
('purged-body', """	rc = find_cl_first(mdtname, 0, oldest@@);
	if (rc < 0) {
		llapi_error(LLAPI_MSG_ERROR, rc,
			    "cannot read the changelog of '%s'", mdtname);
		return rc;
	}
	if (*oldest > anchor + 1) {""", """	rc = find_cl_first(mdtname, 0, oldest@@);
	if (rc < 0)
		return rc;
	if (*oldest > anchor + 1) {"""),
('empty-fn', """ * it; the two look the same, so this warns rather than refuses.
 */
static int find_cookie_was_empty(const char *mdtname, const char *cookie)
{
	__u64 oldest;
	int rc;

	rc = find_cl_first(mdtname, 0, &oldest@@);
	if (rc < 0) {
		llapi_error(LLAPI_MSG_ERROR, rc,
			    "cannot read the changelog of '%s'", mdtname);
		return rc;
	}
	if (oldest > 1)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "'%s' starts at %llu and was empty when '%s' was written: any records purged since then are not in the answer",
			    mdtname, (unsigned long long)oldest, cookie);

	return 0;
}

""", """ * it; the two look the same, so this warns rather than refuses.  *@oldest
 * is kept for find_cookie_recheck().
 */
static int find_cookie_was_empty(const char *mdtname, const char *cookie,
				 __u64 *oldest)
{
	int rc;

	rc = find_cl_first(mdtname, 0, oldest@@);
	if (rc < 0) {
		llapi_error(LLAPI_MSG_ERROR, rc,
			    "cannot read the changelog of '%s'", mdtname);
		return rc;
	}
	if (*oldest > 1)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "'%s' starts at %llu and was empty when '%s' was written: any records purged since then are not in the answer",
			    mdtname, (unsigned long long)*oldest, cookie);

	return 0;
}

""" + RECHECK),
('check-doc', """ * was empty, and only warns: see find_cookie_was_empty().  llapi_find_since()
 * reads one more before each MDT, for a purge during the run.
""", """ * was empty, and only warns: see find_cookie_was_empty().  llapi_find_since()
 * reads one more before each MDT, for a purge during the run: see
 * find_cookie_recheck(), which gets what this saw for those in @seen.
"""),
('check-sig', """			     const __u64 *starts, __u64 *reached)
{""", """			     const __u64 *starts, __u64 *reached,
			     __u64 *seen)
{"""),
('check-empty', """			rc = find_cookie_was_empty(mdtname, cookie);
""", """			rc = find_cookie_was_empty(mdtname, cookie, &seen[i]);
"""),
('check-purged', """		rc = find_cookie_purged(mdtname, anchor, cookie, &oldest);
		if (rc < 0)
			return rc;
		if (oldest == 0)
			continue;
""", """		rc = find_cookie_purged(mdtname, anchor, cookie, &oldest);
		if (rc < 0 && rc != -ESTALE)
			llapi_error(LLAPI_MSG_ERROR, rc,
				    "cannot read the changelog of '%s'",
				    mdtname);
		if (rc < 0)
			return rc;
		if (oldest == 0)
			continue;
"""),
('decl', """	__u64 *reached = NULL;
	int i;
	int rc;
""", """	__u64 *reached = NULL;
	__u64 *seen = NULL;
	int i;
	int rc;
"""),
('alloc', """	reached = calloc(mdt_bound, sizeof(*reached));
	if (mdts == NULL || starts == NULL || reached == NULL) {
""", """	reached = calloc(mdt_bound, sizeof(*reached));
	seen = calloc(mdt_bound, sizeof(*seen));
	if (mdts == NULL || starts == NULL || reached == NULL ||
	    seen == NULL) {
"""),
('call', """				       mdt_count, starts, reached);
""", """				       mdt_count, starts, reached, seen);
"""),
('loop', """		 * reading: one record, as there.  The cookie is not
		 * rewritten, so every later run is refused the same way
		 * until it is removed, rather than skip the records.
		 */
		if (param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0 &&
		    starts[mdts[i]] != FIND_COOKIE_NONE) {
			rc = find_cookie_purged(mdtname, starts[mdts[i]],
						param->fp_since_cookie, NULL);
			if (rc < 0)
				break;
		}
""", """		 * reading: one record, as there.  On -ESTALE the cookie is
		 * not rewritten, so the next run sees the purge too rather
		 * than skip the records.  A failed read is a failed scan.
		 */
		rc = 0;
		if (param->fp_since_cookie != NULL)
			rc = find_cookie_recheck(mdtname, starts[mdts[i]],
						 seen[i],
						 param->fp_since_cookie);
		if (rc == -ESTALE)
			break;
"""),
# 69443's state of the scan call; 69500 has find_since_gap() before it
('scan443', """
		rc = llapi_scan_changelog(&sc, find_since_cand_cb, &st);
		if (rc < 0) {""", """
		if (rc == 0)
			rc = llapi_scan_changelog(&sc, find_since_cand_cb,
						  &st);
		if (rc < 0) {"""),
('gap500', """
		rc = find_since_gap(param, st.fss_since, mdtname);
		if (rc == 0)
			rc = llapi_scan_changelog(&sc, find_since_cand_cb,
						  &st);
""", """
		if (rc == 0)
			rc = find_since_gap(param, st.fss_since, mdtname);
		if (rc == 0)
			rc = llapi_scan_changelog(&sc, find_since_cand_cb,
						  &st);
"""),
('free', """	free(reached);
	if (st.fss_mnt_fd >= 0)""", """	free(reached);
	free(seen);
	if (st.fss_mnt_fd >= 0)"""),
# --- 69729 (1)
('igif', """	 * Built, not non-empty: an MDT other than MDT0000 whose files all
	 * sit in the filesystem root ends the pre-pass with dm_used == 0 --
	 * it has no directory with a linkea -- and composing still answers,
	 * scan_dirmap_path() stopping at LU_ROOT_FID without a lookup.  An
""", """	 * Built, not non-empty: an MDT other than MDT0000 whose files all
	 * sit in the filesystem root usually ends the pre-pass with
	 * dm_used == 0 (no directory with a linkea, unless LFSCK made
	 * lost+found/MDT000N there), and composing still answers,
	 * scan_dirmap_path() stopping at LU_ROOT_FID without a lookup.  An
"""),
],
LF: [
('lf-443', """that reaches it after the first test is refused then. The matches
already printed stay printed, and
.I FILE
is not rewritten, so every later run is refused the same way until
.I FILE
is removed. Not caught: a purge that empties that log, until new records
arrive; a purge on the MDT being read, which on a single-MDT filesystem is
the only window there is.""", """that reaches it after the first test is refused then. So is any purge,
after the first test, of an MDT recorded at 0 whose log then held records.
The matches already printed stay printed, and
.I FILE
is not rewritten, so every later run is refused the same way until
.I FILE
is removed, or warned for an MDT recorded at 0. Not caught: a purge that
empties the log of an MDT recorded past 0, until new records arrive; records
made and purged during the run on an MDT whose log was empty when it began;
a purge on the MDT being read, which on a single-MDT filesystem is the only
window there is."""),
],
FS: [
('fs-443', """a clear that lands on it after the first test ends the call
with this error, after the earlier MDTs' matches were reported.
.I fp_since_cookie
is not rewritten, so every later call fails the same way until it is
removed. Not seen: a clear that empties that log, until new records arrive,
and a clear on the MDT being read.""", """a clear that lands on it after the first test ends the call
with this error, after the earlier MDTs' matches were reported. So does any
clear, after the first test, of an MDT anchored at 0 whose log then held
records.
.I fp_since_cookie
is not rewritten, so every later call fails the same way until it is
removed, or warns for an MDT anchored at 0. Not seen: a clear that empties
the log of an MDT anchored past 0, until new records arrive; records made and
cleared during the call on an MDT whose log was empty when it began; and a
clear on the MDT being read."""),
# --- 68419 (2)
('fs-einval', """filesystem or another search root, or that has text in it but no line that
.B lfs find
writes.""", """filesystem or another search root, that names no search root in its header,
or that has text in it but no line that
.B lfs find
writes, and for an empty cookie name."""),
],
SF: [
# --- 68416 (1)
('sf-eacces', """.B -EACCES
the object, if it is a directory, or else its parent could not be opened for
reading. Only a caller without
.B CAP_DAC_READ_SEARCH
on a mount with
.B -o user_fid2path
meets this: the FID lookup itself checks no permission. A
.I lfsp_want
naming no field this call gathers opens nothing and is not affected.""", """.B -EACCES
the object, or a directory on the way to it, could not be searched or opened.
A caller without
.B CAP_DAC_READ_SEARCH
(on a mount with
.BR "-o user_fid2path" ),
or root on a client with root squash, can meet this. The FID lookup itself
checks no permission."""),
],
SC: [
# --- 68415 (1)
('sc-mark', """means in every scanner that fills it. Only a resolve can answer the owner.
""", """means in every scanner that fills it. Only a resolve can answer the owner.
The
.I lfsr_name
of a
.B CL_MARK
record is the name of the MDT that wrote it.
"""),
],
}

G443 = {'purged-doc', 'purged-body', 'empty-fn', 'check-doc', 'check-sig',
        'check-empty', 'check-purged', 'decl', 'alloc', 'call', 'loop',
        'scan443', 'gap500', 'free'}

def fn(path, s, subj):
    for key, o, n in R.get(path, []):
        if key in G443 and 'static int find_cookie_purged(' not in s:
            continue
        if '@@' in o:
            # 69500 gives find_cl_first() a fourth argument
            four = '__s64 *first_time' in s
            o = o.replace('@@', ', NULL' if four else '')
            n = n.replace('@@', ', NULL' if four else '')
        if key == 'empty-fn' and '__s64 *first_time' in s:
            n = n.replace('find_cl_first(mdtname, 0, &oldest);',
                          'find_cl_first(mdtname, 0, &oldest, NULL);')
        if o in s:
            assert s.count(o) == 1, (subj, key)
            s = s.replace(o, n)
            HITS.setdefault(subj, []).append(key)
    return s

M = {
"LU-20649 llapi: add llapi_scan_changelog()": [(
"""  client mount: one O_PATH open by FID and a statx() per object. It
""", """  client mount: one O_PATH open by FID and a statx() or two per
  object. It
""")],
"LU-20650 lfs: find --since-cookie, check each MDT when read": [(
"""each. If it is past anchor + 1, the run stops with -ESTALE and names
both numbers.
""", """each. If it is past anchor + 1, the run stops with -ESTALE and names
both numbers. An MDT recorded at 0 had nothing consumed, so the
pre-pass keeps the oldest record it saw there, and any change in it
by then, an emptied log included, stops the run the same way.
"""), (
"""than skip the purged records.
""", """than skip the purged records. For an MDT recorded at 0 the next run
warns instead, as it does for any such log that has moved on.

An error reading that record is handled as a failed scan: the MDT is
not read, the run goes on to the next one and fails at the end, so
the cookie is not rewritten.
"""), (
"""Still not covered, and the man pages say so: a purge that empties the
log (seen once new records arrive), a purge on the MDT being read,
which is the only window on a single-MDT filesystem, and a record
written late at the tail of a busy log.
""", """Still not covered, and the man pages say so: a purge that empties the
log of an MDT recorded past 0 (seen once new records arrive), records
made and purged during the run on an MDT whose log was empty when it
began, a purge on the MDT being read, which is the only window on a
single-MDT filesystem, and a record written late at the tail of a busy
log.
""")],
"LU-20650 lfs: find --since, warn when the log was cleared": [(
"""If the read of the oldest record fails, the run stops as it does
when the scan itself fails.
""", """If the read of the oldest record fails, that MDT is not scanned, and
the run goes on and fails at the end, as when the scan itself fails.
""")],
}

def msgfn(msg, subj):
    for o, n in M.get(subj, []):
        assert o in msg, (subj, o[:40])
        msg = msg.replace(o, n)
        HITS.setdefault(subj, []).append('msg')
    return msg

import atexit
@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
