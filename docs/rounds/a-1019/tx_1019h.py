# a-1019 lreview r3 on 68419 (0f9b013492), applied by forktx5.py from 68419
# up, on every branch that holds it (the trunk only):
#   S4  find_cookie_check(): the third read, after the second found nothing
#       at or after the anchor, continued on oldest >= anchor.  A purge of
#       anchor+1..K by another user between the second and third reads gave
#       oldest = K+1 and the run resumed at anchor+1 with them gone.  Now
#       oldest == 0 or anchor + 1 continues, past anchor + 1 is the -ESTALE
#       purge refusal, and oldest <= anchor the restart refusal.  68419 has
#       the purge check inline; from 69443 on it calls find_cookie_purged(),
#       whichever find_cl_first() the commit has.
#   S5  the header sscanf width is FIND_COOKIE_WIDTH(NAME_MAX), not 255.
# Anchor 0 (find_cookie_was_empty(), WARN and continue) is not touched.
# Idempotent: every old text is gone after one pass.
HITS = {}
ANC = frozenset()

PF = 'lustre/utils/liblustreapi_pfind.c'
CID_68419 = 'Ia8ce93368a2c2c8c2ea2ee88c8e7f7e099b1bfa5'


def base(path):
    raise RuntimeError('set by the driver')


R = []      # (tag, path, old, new)

R.append(('S5', PF,
'''		if (sscanf(line, "# lfs find --since-cookie for %255s%n",
			   name, &pos) == 1) {
''',
'''		if (sscanf(line, "# lfs find --since-cookie for %"
			   FIND_COOKIE_WIDTH(NAME_MAX) "s%n",
			   name, &pos) == 1) {
'''))

# 68419: find_cl_first() takes three arguments, the purge check is inline
R.append(('S4-68419', PF,
'''			/*
			 * A clear between the two reads leaves the log empty,
			 * or holding only newer records.  Nothing was lost.
			 */
			rc = find_cl_first(mdtname, 0, &oldest);
			if (rc < 0) {
				llapi_error(LLAPI_MSG_ERROR, rc,
					    "cannot read the changelog of '%s'",
					    mdtname);
				return rc;
			}
			if (oldest == 0 || oldest >= anchor)
				continue;
''',
'''			/*
			 * A clear between the two reads leaves the log empty,
			 * or starting at anchor + 1.  Past that is a purge.
			 */
			rc = find_cl_first(mdtname, 0, &oldest);
			if (rc < 0) {
				llapi_error(LLAPI_MSG_ERROR, rc,
					    "cannot read the changelog of '%s'",
					    mdtname);
				return rc;
			}
			if (oldest == 0 || oldest == anchor + 1)
				continue;
			if (oldest > anchor + 1) {
				llapi_error(LLAPI_MSG_ERROR |
					    LLAPI_MSG_NO_ERRNO, -ESTALE,
					    "'%s' has purged past the cookie: it starts at %llu and '%s' records %llu, so the run would resume at %llu and the records in between are gone",
					    mdtname, (unsigned long long)oldest,
					    cookie, (unsigned long long)anchor,
					    (unsigned long long)(anchor + 1));
				return -ESTALE;
			}
'''))

# 69443 on: find_cookie_purged() exists (69500 gives find_cl_first() a
# fourth argument), so the third read calls it
R.append(('S4-69443', PF,
'''			/*
			 * A clear between the two reads leaves the log empty,
			 * or holding only newer records.  Nothing was lost.
			 */
			rc = find_cl_first(mdtname, 0, &oldest, NULL);
			if (rc < 0) {
				llapi_error(LLAPI_MSG_ERROR, rc,
					    "cannot read the changelog of '%s'",
					    mdtname);
				return rc;
			}
			if (oldest == 0 || oldest >= anchor)
				continue;
''',
'''			/*
			 * A clear between the two reads leaves the log empty,
			 * or starting at anchor + 1.  Past that is a purge.
			 */
			rc = find_cookie_purged(mdtname, anchor, cookie,
						&oldest);
			if (rc < 0 && rc != -ESTALE)
				llapi_error(LLAPI_MSG_ERROR, rc,
					    "cannot read the changelog of '%s'",
					    mdtname);
			if (rc < 0)
				return rc;
			if (oldest == 0 || oldest == anchor + 1)
				continue;
'''))


P69443 = R[-1][3]


def fn(path, s, subj):
    if s is None or CID_68419 not in ANC:
        return s
    for tag, p, o, n in R:
        if p != path or o not in s:
            continue
        if tag == 'S4-68419' and 'static int find_cookie_purged(' in s:
            tag, n = 'S4-69443', P69443
        assert s.count(o) == 1, (tag, subj, s.count(o))
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-50s %s' % (k[:50], ' '.join(v)), file=sys.stderr)
