# a1018 pass f2 (69443 lreview nit): the anchor-0 recheck warning names the
# current oldest too, or says the log is now empty.  Start: 69443 df82f49a83.
PF = 'lustre/utils/liblustreapi_pfind.c'
HITS = {}
O = """	/* as find_cookie_was_empty(): warn, and the cookie advances */
	llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
		    "'%s' started at %llu when the search began and has been purged since: records purged during the run may be missing from the answer",
		    mdtname, (unsigned long long)seen);
	return 0;
"""
N = """	/* as find_cookie_was_empty(): warn, and the cookie advances */
	if (oldest == 0)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "'%s' started at %llu when the search began and has been purged since, and is now empty: records purged during the run may be missing from the answer",
			    mdtname, (unsigned long long)seen);
	else
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "'%s' started at %llu when the search began and has been purged since, and now starts at %llu: records purged during the run may be missing from the answer",
			    mdtname, (unsigned long long)seen,
			    (unsigned long long)oldest);
	return 0;
"""
def fn(path, s, subj):
    if path == PF and O in s:
        assert s.count(O) == 1, subj
        s = s.replace(O, N)
        HITS.setdefault(subj, []).append('warn')
    return s
import atexit, sys
@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
