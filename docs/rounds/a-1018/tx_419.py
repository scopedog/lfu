# AI on 68419 PS23:
# 6b5da815: a sanity.sh comment described an earlier revision of 160Ac.
# 397172d9 (real defect): an MDT whose log was empty got no cookie line, so
#   the next run read it as never anchored, did not probe it, and lost any
#   records made and purged in between with nothing said.  Now every covered
#   MDT gets a line, 0 for an empty log; starts[] tells "no line"
#   (FIND_COOKIE_NONE) from 0; an anchor of 0 whose log now starts past 1
#   WARNS rather than refuses -- a log drained before the empty run looks
#   the same, and refusing would stop every later run for good.  69443's
#   per-MDT recheck skips both.
PF = 'lustre/utils/liblustreapi_pfind.c'
SH = 'lustre/tests/sanity.sh'
LF = 'Documentation/man1/lfs-find.1'
FS = 'Documentation/man3/llapi_find_since.3'
HELPER = """/*
 * An anchor of 0: the MDT's log was empty when the cookie was written.  If it
 * now starts past 1, records may have been purged since that run or before
 * it; the two look the same, so this warns rather than refuses.
 */
static int find_cookie_was_empty(const char *mdtname, const char *cookie)
{
	__u64 oldest;
	int rc;

	rc = find_cl_first(mdtname, 0, &oldest);
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

"""
STALE = """/*
 * The stale-anchor check, which is the reason a cookie is worth having:
"""
R = {
PF: [
("""#define FIND_COOKIE_IDX_LEN	31
""", """#define FIND_COOKIE_IDX_LEN	31
/* starts[] for an MDT the cookie has no line for; 0 is an empty log */
#define FIND_COOKIE_NONE	(~0ULL)
"""),
(""" * by MDT number and already carries the values read from the file, updated
 * in place for the MDTs this run reached.
 */
""", """ * by MDT number and already carries the values read from the file, updated
 * in place for the MDTs this run reached.  A covered MDT is written even at
 * 0, an empty log, so the next run can tell it from one never read.
 */
"""),
("""		if (seen[i] == 0)
			continue;	/* never anchored: same as absent */
""", """		if (seen[i] == FIND_COOKIE_NONE)
			continue;	/* neither in the file nor covered */
"""),
(STALE, HELPER + STALE),
# 68419's kernel-doc, then 69443's
(""" * three records per anchored MDT, and none for an MDT with no anchor yet: 0
 * has nothing to be stale against, and that is also every MDT of a first
 * run.
 *
""", """ * three records per anchored MDT, and none for an MDT the cookie has no line
 * for: that is every MDT of a first run.  An anchor of 0 is an MDT whose log
 * was empty, and only warns: see find_cookie_was_empty().
 *
"""),
(""" * three records per anchored MDT, and none for an MDT with no anchor yet: 0
 * has nothing to be stale against, and that is also every MDT of a first
 * run.  llapi_find_since() reads one more before each MDT, for a purge
 * during the run.
""", """ * three records per anchored MDT, and none for an MDT the cookie has no line
 * for: that is every MDT of a first run.  An anchor of 0 is an MDT whose log
 * was empty, and only warns: see find_cookie_was_empty().  llapi_find_since()
 * reads one more before each MDT, for a purge during the run.
"""),
("""		/* what this run inherits, until the scan moves it on */
		reached[i] = anchor;
		if (anchor == 0)
			continue;

		snprintf(mdtname, sizeof(mdtname), "%s-MDT%04x", fsname,
			 mdts[i]);
""", """		/* what this run inherits, until the scan moves it on */
		reached[i] = anchor != FIND_COOKIE_NONE ? anchor : 0;
		if (anchor == FIND_COOKIE_NONE)
			continue;

		snprintf(mdtname, sizeof(mdtname), "%s-MDT%04x", fsname,
			 mdts[i]);
		if (anchor == 0) {
			rc = find_cookie_was_empty(mdtname, cookie);
			if (rc < 0)
				return rc;
			continue;
		}
"""),
("""	if (mdts == NULL || starts == NULL || reached == NULL) {
		rc = -ENOMEM;
		goto out;
	}
""", """	if (mdts == NULL || starts == NULL || reached == NULL) {
		rc = -ENOMEM;
		goto out;
	}
	for (i = 0; i < mdt_bound; i++)
		starts[i] = FIND_COOKIE_NONE;
"""),
("""			sc.lfsc_startrec = starts[mdts[i]] != 0 ?
					 starts[mdts[i]] + 1 : 0;
""", """			sc.lfsc_startrec =
				starts[mdts[i]] != FIND_COOKIE_NONE ?
				starts[mdts[i]] + 1 : 0;
"""),
# 69443's per-MDT recheck: an anchor of 0 only warned
("""		if (param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0) {
""", """		if (param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0 &&
		    starts[mdts[i]] != FIND_COOKIE_NONE) {
"""),
],
SH: [
("""	# Both of these run while the cookie is still fresh, which is the
	# right order but not for the reason it once said: neither refusal
	# can be preempted by the staleness check.  llapi_find_since() tests
	# --since against --since-cookie in its first block, and lfs_find()
	# rejects a second path before it calls llapi_find_since() at all.
""", """	# Both run while the cookie is still fresh, though neither refusal
	# can be preempted by the staleness check: llapi_find_since() tests
	# --since against --since-cookie in its first block, and lfs_find()
	# rejects a second path before it calls llapi_find_since().
"""),
("""	[[ -L $ck.link ]] || error "the symlinked cookie was replaced"

	rm -rf $DIR/$tdir
""", """	[[ -L $ck.link ]] || error "the symlinked cookie was replaced"

	# An empty log is written as 0, not left out, so records made and
	# purged before the next run are warned of rather than lost unsaid
	stack_trap "rm -f $ck.empty"
	changelog_clear 0 || error "changelog_clear failed"
	$LFS find $DIR/$tdir --since-cookie $ck.empty -type f > /dev/null ||
		error "a run over an empty log failed"
	grep -q "^$FSNAME-MDT0000 0$" $ck.empty ||
		error "an empty log left no line: $(cat $ck.empty)"
	createmany -o $DIR/$tdir/lost 5 || error "createmany failed"
	sync; sleep 2
	changelog_clear 0 || error "changelog_clear failed"
	touch $DIR/$tdir/kept || error "touch kept failed"
	sync; sleep 2
	out=$($LFS find $DIR/$tdir --since-cookie $ck.empty -type f 2>&1) ||
		error "the run after an empty one failed: $out"
	grep -q "was empty when" <<< "$out" ||
		error "records purged after an empty run gave no warning: $out"
	grep -q "/kept$" <<< "$out" ||
		error "the run after an empty one missed kept: $out"

	rm -rf $DIR/$tdir
"""),
],
LF: [
("""that does not exist is a first run and starts at the oldest surviving record;
one that cannot be written is refused before the search prints anything.
""", """that does not exist is a first run and starts at the oldest surviving record;
one that cannot be written is refused before the search prints anything.
An MDT that
.I FILE
has no line for is read as a first run too. Every MDT a run reads gets a
line, 0 for an empty log. If that log later starts past record 1, the next
run warns and goes on: records purged after the empty run cannot be told
from ones purged before it.
"""),
],
FS: [
("""first run, which reads every log from its beginning. The call reads the
""", """first run, which reads every log from its beginning, and so is a missing
line for one MDT. Every MDT the call reads gets a line, 0 for an empty log;
if that log later starts past record 1, the next call warns and goes on,
since records purged after the empty run cannot be told from ones purged
before it. The call reads the
"""),
],
}
def fn(path, s, subj):
    if path == PF and 'FIND_COOKIE_IDX_LEN' not in s:
        return s
    for o, n in R.get(path, []):
        if o in s:
            assert s.count(o) == 1, (path, o[:50])
            # 69500 gives find_cl_first() a fourth argument
            if o == STALE and '__s64 *first_time' in s:
                n = n.replace('find_cl_first(mdtname, 0, &oldest);',
                              'find_cl_first(mdtname, 0, &oldest, NULL);')
            s = s.replace(o, n)
    return s
S419 = "LU-20650 lfs: add find --since-cookie, a per-MDT anchor"
M419 = [("""repeat them.  An MDT with no anchor is not probed at all -- 0 has
nothing to be stale against, and that is every MDT of a first run.
""", """repeat them.  An MDT with no line in the cookie is not probed at all:
it has nothing to be stale against, and that is every MDT of a first
run.

Every MDT a run read gets a line, "<mdtname> 0" for an empty log, so
the next run can tell "empty when last read" from "never read".
Writing nothing for it would lose, with nothing said, any records made
and purged before the next run.  Such an anchor is probed too, but a
log that now starts past 1 only warns: records purged after the empty
run cannot be told from records purged before it, and refusing would
stop every later run on an MDT whose log a policy engine had drained.
"""), ("""still be there afterwards. One has no search root in its header, and is
refused too.
""", """still be there afterwards. One has no search root in its header, and is
refused too.

Last, 160Ac runs a new cookie over an empty log and checks that it
holds "MDT0000 0", then makes and purges records and checks that the
next run warns and still finds the record made after the purge.
""")]
def msgfn(msg, subj):
    if subj == S419:
        for o, n in M419:
            assert o in msg, '419 msg anchor ' + o[:30]
            msg = msg.replace(o, n)
    return msg
