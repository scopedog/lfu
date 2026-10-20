# a-1019 lreview r2 fixes on 68415 (lreview/68415-r2.md), applied by
# forktx5.py to every commit from 68415 up, on every branch:
#   1 sanity 56Eea skips test11 too on an MDS below 2.17.0
#   2 commit message: twelve cases, not eleven
#   3 commit message: test11 needs -u too
# Idempotent: every old text is gone after one pass.
HITS = {}
ANC = frozenset()

SAN = 'lustre/tests/sanity.sh'


def base(path):
    raise RuntimeError('set by the driver')


R = []      # (tag, path, old, new)

R.append(('S1', SAN,
'''	# test9 asks the MDS for the user's mask, with a key the MDS has
	# only from 2.17.0 (LU-19296); a clear in test6 purges the log only
	# when no other changelog user holds it back.  Either skips that
	# case alone.
	local users=$(do_facet mds1 $LCTL get_param -n \\
		mdd.$(facet_svc mds1).changelog_users | grep -c "^cl")
	local skip_cases=""

	(( MDS1_VERSION >= $(version_code 2.17.0) )) || skip_cases="9"
''',
'''	# test9 and test11 ask the MDS for the user's mask, with a key the
	# MDS has only from 2.17.0 (LU-19296); a clear in test6 purges the
	# log only when no other changelog user holds it back.  Each check
	# skips only its own cases.
	local users=$(do_facet mds1 $LCTL get_param -n \\
		mdd.$(facet_svc mds1).changelog_users | grep -c "^cl")
	local skip_cases=""

	(( MDS1_VERSION >= $(version_code 2.17.0) )) || skip_cases="9,11"
'''))


def fn(path, s, subj):
    if s is None:
        return s
    for tag, p, o, n in R:
        if p != path or o not in s:
            continue
        assert s.count(o) == 1, (tag, subj, s.count(o))
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


M = {
    'M23': (
        '''llapi_scan_changelog_test has eleven cases and sanity 56Eea runs it.
It takes -m for the MDT, -u for a registered changelog user and -d for
a client mount. test6 and test9 need -u and skip without it.
''',
        '''llapi_scan_changelog_test has twelve cases and sanity 56Eea runs it.
It takes -m for the MDT, -u for a registered changelog user and -d for
a client mount. test6, test9 and test11 need -u and skip without it.
'''),
}


def msgfn(msg, subj):
    for tag, (o, n) in M.items():
        if o in msg:
            msg = msg.replace(o, n)
            HITS.setdefault(subj, []).append('msg-' + tag)
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-50s %s' % (k[:50], ' '.join(v)), file=sys.stderr)
