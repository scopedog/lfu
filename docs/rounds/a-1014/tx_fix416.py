# lreview on 68416': -ENOTDIR retried; -ESTALE described as what is left
# after the retry; the message stops describing hunks the fork moved out.
C = 'lustre/utils/liblustreapi_scan.c'
M = 'Documentation/man3/llapi_scan_fid.3'
R = {
C: [(
"""	 * The object or a directory above it may have been renamed between
	 * the fid2path and the steps after it, which then miss a live
	 * object.  Ask for the name again: no name means it is gone, and a
	 * new name is gathered there.
	 */
	if (ours && (rc == -ENOENT || rc == -ESTALE) &&
""",
"""	 * The object or a directory above it may have been renamed between
	 * the fid2path and the steps after it, which then miss a live
	 * object.  Ask for the name again: no name means it is gone, and a
	 * new name is gathered there.  -ENOTDIR is a file made where a
	 * renamed directory was.
	 */
	if (ours && (rc == -ENOENT || rc == -ESTALE || rc == -ENOTDIR) &&
""")],
M: [(
"""An object renamed during the call, or under a directory that was, is not
reported gone: when the name the lookup gave is missing or holds another
object, the lookup is repeated, a few times at most, and the record is
gathered at the new name.
""",
"""An object renamed during the call, or under a directory that was, is not
reported gone: when the name the lookup gave is missing, holds another
object or goes through what is no longer a directory, the lookup is
repeated, a few times at most, and the record is gathered at the new name.
A name unlinked and recreated during the call answers this too: the
repeated lookup finds the object gone.
"""), (
""".I fid
resolved to no longer holds it: it was unlinked and recreated while the
record was being gathered, so the record would have described a different
object. Only a
""",
""".I fid
resolved to still holds another object when the lookup is repeated, so the
record would describe a different object: a directory shard's or an OST
object's FID, a name no longer on Lustre, or client modules with only the V1
getinfo ioctl; see
.BR ERRORS .
Only a
"""), (
"""the name it resolved to holds a different object now, or is no longer on
Lustre.""",
"""the name it resolved to still holds a different object when the lookup is
repeated, or is no longer on Lustre.""")],
}
def fn(path, s, subj):
    for old, new in R.get(path, []):
        if old in s:
            s = s.replace(old, new)
    return s
O1 = """runs against a pathname, so the FID it found is checked against the
one asked for and a name unlinked and recreated underneath it answers
-ESTALE rather than a record for a different object.
"""
N1 = """runs against a pathname, so the FID it found is checked against the
one asked for, and a record never describes a different object.
-ESTALE is what is left when the name still holds another object after
the lookup is repeated (below): a shard's or an OST object's FID, a
name off Lustre, or V1-only client modules.  A name unlinked and
recreated answers -ENOENT, the object being gone.
"""
O2 = """Only lfsp_want, lfsp_filter and lfsp_got are used from the parameter
block.
lfsp_max_depth, lfsp_stats, lfsp_search and lfsp_fsname describe a
traversal there is none of and are ignored; lfsp_thread_count above 1
is refused rather than ignored, because a caller setting it has
misunderstood the call.
"""
N2 = """Only lfsp_want, lfsp_filter and lfsp_got are used from the parameter
block.  lfsp_max_depth and lfsp_stats describe a traversal there is
none of and are ignored; lfsp_thread_count above 1 is refused rather
than ignored, because a caller setting it has misunderstood the call.
"""
O3 = """llapi_find_device() clears lfsp_got.  scan_param_copyin() copies the
caller's block whole, so the caller's pointer came through and was
answered with find's own demand mask -- a mask for a question the
caller never asked.  The field's kernel-doc is rewritten with it, to
say that it is per scan rather than per library and why it is reached
through a pointer.

"""
O4 = """that window, and a directory's rename logs no record for the objects
under it, so a changelog consumer would drop a live object for good.
The name is looked up again, three times at most: no name means the
object is gone, and a new name is gathered there.
"""
N4 = """that window, and a directory's rename logs no record for the objects
under it, so a changelog consumer would drop a live object for good.
The name is looked up again, three times at most: no name means the
object is gone, and a new name is gathered there.  -ENOTDIR is retried
too: it is what a file made where a renamed directory was gives.
"""
P159 = """llapi_find_device() clears lfsp_got.  scan_param_copyin() copies the
caller's block whole, so the caller's pointer came through and was
answered with find's own demand mask -- a mask for a question the
caller never asked.
"""
P288 = """The kernel-doc of lfsp_got now says that it is per scan rather than
per library -- an OST answers LLAPI_SCAN_OWNER where an MDT answers
LLAPI_SCAN_LMV -- and why it is reached through a pointer.
llapi_scan_fid() ignores lfsp_search and lfsp_fsname as well, and its
page and kernel-doc say so.
"""
def add_para(m, p):
    lines = m.rstrip('\n').split('\n')
    i = next(k for k, l in enumerate(lines)
             if l.startswith(('Test-Parameters:', 'Signed-off-by:')))
    return '\n'.join(lines[:i]).rstrip('\n') + '\n\n' + p + '\n' + '\n'.join(lines[i:]) + '\n'
def msgfn(m, subj):
    if subj.startswith('LU-20650 llapi: fill a scan record for one FID'):
        for o, n in ((O1, N1), (O2, N2), (O3, ''), (O4, N4)):
            assert m.count(o) == 1, o[:40]
            m = m.replace(o, n)
    elif subj.startswith('LU-20611 llapi: run find over a device scan'):
        m = add_para(m, P159)
    elif subj.startswith("LU-20637 llapi: name a device scan's objects"):
        m = add_para(m, P288)
    return m
