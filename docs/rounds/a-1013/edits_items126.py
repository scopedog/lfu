#!/usr/bin/env python3
# Apply the 10-13 lreview items 1, 2 and 6 to whatever version of the two
# files is given; idempotent.  Usage: edits.py <pfind.c> <llapi_find_device.3>
import re, sys

def once(s, old, new, what):
    if new in s:
        return s
    assert s.count(old) == 1, (what, s.count(old))
    return s.replace(old, new)

def pfind(s):
    # ---- item 2
    s = once(s, '''static bool find_lmv_rejects(const struct find_param *param, bool have_lmv)
{
	struct lmv_user_md *lmv = param->fp_lmv_md;

	if (!param->fp_get_lmv)
		return false;

	/* no stripe of its own: rejected unless --foreign is negated */
	if (!have_lmv && param->fp_check_foreign)
		return !param->fp_exclude_foreign;
''', '''static bool find_lmv_rejects(const struct find_param *param, bool have_lmv,
			     bool not_foreign)
{
	struct lmv_user_md *lmv = param->fp_lmv_md;

	if (!param->fp_get_lmv)
		return false;

	/*
	 * No stripe of its own: rejected unless --foreign is negated.  A
	 * walk stops here, its caller printing the directory.  A scan passes
	 * @not_foreign and goes on to the other stripe tests.
	 */
	if (!have_lmv && param->fp_check_foreign && !not_foreign)
		return !param->fp_exclude_foreign;
''', 'lmv_rejects')
    s = once(s, '''	 * save the getattr.  A target scan has the attributes already, so it
	 * goes on to the attribute tests.  The stripe tests (--mdt-count,
	 * --mdt-hash) stay skipped, as on a walk: see find_lmv_rejects().
	 */''', '''	 * save the getattr.  A target scan has the attributes already, so it
	 * skips only the --foreign test and goes on to the others.
	 */''', 'comment')
    s = once(s, '''	if (find_lmv_rejects(param, fc->fc_rec->lfsr_valid & LLAPI_SCAN_LMV))
		return 0;''', '''	if (find_lmv_rejects(param, fc->fc_rec->lfsr_valid & LLAPI_SCAN_LMV,
			     not_foreign))
		return 0;''', 'call1')
    s = once(s, '''find_lmv_rejects(param, have_lmv))''',
             '''find_lmv_rejects(param, have_lmv, false))''', 'call2')
    # ---- item 1
    s = once(s, '''			 * ! -btime does match it, as for find(1) and as for
			 * --projid above: the negation of a false test.
			 */
			if (param->fp_exclude_btime)
				goto btime_done;
			if (path == NULL)
				fc->fc_undecided = true;
			return 0;
''', '''			 * ! -btime does match it, as for find(1) and as for
			 * --projid above: the negation of a false test.
			 *
			 * Not on a target scan.  Over a mount the MDS gives
			 * such an inode a birth time of 0, so a walk answers
			 * both forms from that.  The scan cannot say what the
			 * mount would, and counts both forms undecided.
			 */
			if (path == NULL) {
				fc->fc_undecided = true;
				return 0;
			}
			if (param->fp_exclude_btime)
				goto btime_done;
			return 0;
''', 'btime')
    # ---- item 6, inside llapi_find_device() only
    i = s.index('\nint llapi_find_device(')
    head, f = s[:i], s[i:]
    f = once(f, '''	struct llapi_scan_stats stats = { .ss_size = sizeof(stats) };
''', '''	struct llapi_scan_stats stats = { .ss_size = sizeof(stats) };
	struct llapi_scan_stats *ustats = NULL;	/* the caller's, if any */
''', 'decl')
    f = once(f, '''		rc = scan_param_copyin(&spl, sp, LLAPI_SCAN_F_KNOWN_DEV);
		if (rc != 0)
			return rc;
	}
''', '''		rc = scan_param_copyin(&spl, sp, LLAPI_SCAN_F_KNOWN_DEV);
		if (rc != 0)
			return rc;
		/* filled after the scan, as llapi_scan_device() fills it */
		ustats = spl.lfsp_stats;
		if (ustats != NULL &&
		    ustats->ss_size < LLAPI_SCAN_STATS_MIN_SIZE)
			return -EINVAL;
	}
''', 'copyin')
    out = '''	/*
	 * The scan's counters, so a program can see a partial answer and
	 * not only a message: ss_skipped is what could not be read.
	 * ss_emitted counts the records the search judged, not its matches.
	 */
	if (ustats != NULL) {
		__u32 size = ustats->ss_size;

		if (size > sizeof(stats))
			size = sizeof(stats);
		size = scan_stats_whole(size);
		stats.ss_size = size;
		memcpy(ustats, &stats, size);
		stats.ss_size = sizeof(stats);
	}
'''
    if out not in f:
        m = list(re.finditer(r'\trc = (llapi_scan_device|scan_device_run_prepass)'
                             r'\(target, &spl, find_device_cb, &st[^;]*;\n', f))
        assert len(m) == 1, ('scan call', len(m))
        f = f[:m[0].end()] + out + f[m[0].end():]
    return head + f

STATS = '''.I lfsp_stats
is filled as
.BR llapi_scan_device (3)
fills it, so a program can see that part of the target was skipped.
Its
.I ss_emitted
counts the objects the search judged, not the ones it matched.
'''

def man(s):
    if STATS in s:
        return s
    v1 = '''as it does for a scan.  Four of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.IR lfsp_thread_count ,
.I lfsp_stats
and
.IR lfsp_filter .
The last goes because there is no caller data to pair a filter with: the
'''
    v2 = '''as it does for a scan.  Five of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.IR lfsp_thread_count ,
.IR lfsp_stats ,
.I lfsp_filter
and
.IR lfsp_got .
'''
    if v1 in s:
        return s.replace(v1, '''as it does for a scan.  Three of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.I lfsp_thread_count
and
.IR lfsp_filter .
''' + STATS + '''.I lfsp_filter
goes because there is no caller data to pair a filter with: the
''')
    assert s.count(v2) == 1, 'man v2'
    return s.replace(v2, '''as it does for a scan.  Four of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.IR lfsp_thread_count ,
.I lfsp_filter
and
.IR lfsp_got .
''' + STATS)

for path, fn in ((sys.argv[1], pfind), (sys.argv[2], man)):
    s = open(path).read()
    t = fn(s)
    if t != s:
        open(path, 'w').write(t)
