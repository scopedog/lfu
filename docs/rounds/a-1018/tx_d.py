# a1018 pass d (user 10-18): in 69443's find_cookie_recheck(), an MDT recorded
# at 0 whose oldest record moved during the run WARNS and goes on (no -ESTALE);
# the cookie advances as usual.  Man pages: that, plus "Not caught" gains a
# purge during the run of an MDT with no cookie line (a first run).
PF = 'lustre/utils/liblustreapi_pfind.c'
LF = 'Documentation/man1/lfs-find.1'
FS = 'Documentation/man3/llapi_find_since.3'
HITS = {}

R = {
PF: [
('rc-doc', """/*
 * Just before an MDT is read: did a purge reach it after find_cookie_check()?
 * An anchored MDT is tested as there.  One recorded at 0 had nothing
 * consumed, so any move of its oldest record from @seen, an emptied log
 * included, lost records.  One that was empty then (@seen 0) cannot be told.
 *
 * Return: 0, -ESTALE (said here), or the errno reading the log.
 */""", """/*
 * Just before an MDT is read: refuse a purge past its anchor since
 * find_cookie_check().  At anchor 0, only warn if the oldest moved from @seen.
 *
 * Return: 0, -ESTALE (said here), or the errno reading the log.
 */"""),
('rc-tail', """	if (rc < 0 || oldest == seen)
		return rc;
	llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ESTALE,
		    "'%s' started at %llu when the search began and was purged before it was read: those records are not in the answer; '%s' is left where it was",
		    mdtname, (unsigned long long)seen, cookie);
	return -ESTALE;
}""", """	if (rc < 0 || oldest == seen)
		return rc;
	/* as find_cookie_was_empty(): nothing to keep, so the cookie advances */
	llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
		    "'%s' started at %llu when the search began and has been purged since: records purged during the run may be missing from the answer",
		    mdtname, (unsigned long long)seen);
	return 0;
}"""),
],
LF: [
('lf', """that reaches it after the first test is refused then. So is any purge,
after the first test, of an MDT recorded at 0 whose log then held records.
The matches already printed stay printed, and
.I FILE
is not rewritten, so every later run is refused the same way until
.I FILE
is removed; one recorded at 0 is warned of. Not caught: a purge that
empties the log of an MDT recorded past 0, until new records arrive; records
made and purged during the run on an MDT whose log was empty when it began;
a purge on the MDT being read, which on a single-MDT filesystem is the only
window there is. Nor is a record lost to a race in the MDT caught:""", """that reaches it after the first test is refused then. The matches already
printed stay printed, and
.I FILE
is not rewritten, so every later run is refused the same way until
.I FILE
is removed. For an MDT recorded at 0 whose log held records, such a purge
gives a warning that names the MDT instead; the run goes on and
.I FILE
advances as usual, so records purged during the run may be missing. Not
caught: a purge that empties the log of an MDT recorded past 0, until new
records arrive; records made and purged during the run on an MDT whose log
was empty when it began; a purge during the run of an MDT that
.I FILE
has no line for, as on a first run; a purge on the MDT being read, which on
a single-MDT filesystem is the only window there is. Nor is a record lost to
a race in the MDT caught:"""),
],
FS: [
('fs', """with this error, after the earlier MDTs' matches were reported. So does any
clear, after the first test, of an MDT anchored at 0 whose log then held
records.
.I fp_since_cookie
is not rewritten, so every later call fails the same way until it is
removed, or warns for an MDT anchored at 0. Not seen: a clear that empties
the log of an MDT anchored past 0, until new records arrive; records made and
cleared during the call on an MDT whose log was empty when it began; and a
clear on the MDT being read.""", """with this error, after the earlier MDTs' matches were reported.
.I fp_since_cookie
is not rewritten, so every later call fails the same way until it is
removed. Such a clear on an MDT anchored at 0, whose log then held records,
only warns: the call goes on and the cookie advances as usual. Not seen: a
clear that empties the log of an MDT anchored past 0, until new records
arrive; records made and cleared during the call on an MDT whose log was
empty when it began; a clear during the call on an MDT the cookie has no
line for, as on a first call; and a clear on the MDT being read."""),
],
}


def fn(path, s, subj):
    for key, o, n in R.get(path, []):
        if o in s:
            assert s.count(o) == 1, (subj, key)
            s = s.replace(o, n)
            HITS.setdefault(subj, []).append(key)
    return s


S = "LU-20650 lfs: find --since-cookie, check each MDT when read"
M = [(
"""both numbers. An MDT recorded at 0 had nothing consumed, so the
pre-pass keeps the oldest record it saw there, and any change in it
before that MDT is read, an emptied log included, stops the run the
same way.
The matches already printed stay printed. The cookie is not rewritten,
so every later run is refused the same way until it is removed, rather
than skip the purged records. For an MDT recorded at 0 the next run
warns instead, as it does for any such log that has moved on.
""", """both numbers. The matches already printed stay printed. The cookie is
not rewritten, so every later run is refused the same way until it is
removed, rather than skip the purged records.

An MDT recorded at 0 had nothing consumed, so the pre-pass keeps the
oldest record it saw there. If that has changed when the MDT is read,
an emptied log included, the run warns, names the MDT and goes on, as
the pre-pass does for such a log. The cookie advances as usual: the
purged records are gone from the log, so holding it back would get
none of them back and only make the next run repeat this one.
"""), (
"""began, a purge on the MDT being read, which is the only window on a
single-MDT filesystem, and a record written late at the tail of a busy
log.
""", """began, a purge during the run of an MDT the cookie has no line for
(a first run), a purge on the MDT being read, which is the only window
on a single-MDT filesystem, and a record written late at the tail of a
busy log.
""")]


def msgfn(msg, subj):
    if subj != S:
        return msg
    for o, n in M:
        assert o in msg, o[:40]
        msg = msg.replace(o, n)
        HITS.setdefault(subj, []).append('msg')
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
