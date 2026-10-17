# AI on 68415 PS29, 68416 PS29, 68417 PS22.  HAS288 is set by forktx2 per
# commit: True at 68288 (LU-20637) and above, where llapi_scan_rec_path()
# and LLAPI_SCAN_OWNER exist.
HAS288 = False
H = 'include/lustre/lustreapi.h'
CLASS = '#define LLAPI_SCAN_CLASS\t0x0000400000000000ULL\t/* lfsr_class */\n'
EVENT = '#define LLAPI_SCAN_EVENT\t0x0002000000000000ULL'
SHARD = '#define LLAPI_SCAN_LMV_SHARD\t0x0000800000000000ULL'
OWNER = '#define LLAPI_SCAN_OWNER\t0x0001000000000000ULL'
ALWAYS = {
H: [
# 19270dda: reflow
(""" * event is about unless LLAPI_SCAN_CL_F_COALESCE is set).  Return 0 to
 * continue the scan;
 * any other value stops it and is returned to the caller of
 * llapi_scan_namespace(), llapi_scan_device() or llapi_scan_changelog().
""",
""" * event is about unless LLAPI_SCAN_CL_F_COALESCE is set).  Return 0 to
 * continue the scan; any other value stops it and is returned to the caller
 * of llapi_scan_namespace(), llapi_scan_device() or llapi_scan_changelog().
"""),
(""" * event is about unless LLAPI_SCAN_CL_F_COALESCE is set).  Return 0 to
 * continue the scan;
 * any other value stops it and is returned to the caller of
 * llapi_scan_namespace(), llapi_scan_device(), llapi_scan_changelog() or
 * llapi_scan_fid().
""",
""" * event is about unless LLAPI_SCAN_CL_F_COALESCE is set).  Return 0 to
 * continue the scan; any other value stops it and is returned to the caller
 * of llapi_scan_namespace(), llapi_scan_device(), llapi_scan_changelog() or
 * llapi_scan_fid().
"""),
# fa65a621: one blank line
("""int llapi_scan_changelog(const struct llapi_scan_changelog_param *sc,
			 llapi_scan_cb_t cb, void *data);


""",
"""int llapi_scan_changelog(const struct llapi_scan_changelog_param *sc,
			 llapi_scan_cb_t cb, void *data);

"""),
],
# bf6ad7f2: the MDS answers the mask; the client filters
'lustre/tests/sanity.sh': [(
"""	# test9 filters on the server, with a key the MDS has only from
	# 2.17.0 (LU-19296); a clear in test6 purges the log only when no
	# other changelog user holds it back.  Either skips that case alone.
""",
"""	# test9 asks the MDS for the user's mask, with a key the MDS has
	# only from 2.17.0 (LU-19296); a clear in test6 purges the log only
	# when no other changelog user holds it back.  Either skips that
	# case alone.
""")],
}
# below 68288: say nothing of what 68288 brings
BELOW = {
'lustre/utils/liblustreapi_scan_changelog.c': [(
""" * layout, an LMV, HSM state, a linkea, an inode number, a class and an OST
 * object's owner are never filled at any setting, and lfsc_got is what says
 * so before the first record rather than leaving a caller to infer it.
""",
""" * layout, an LMV, HSM state, a linkea, an inode number and a class are
 * never filled at any setting, and lfsc_got is what says so before the
 * first record rather than leaving a caller to infer it.
""")],
'Documentation/man3/llapi_scan_changelog.3': [(
"""an LMV, HSM state, a linkea, an inode number, a class and an OST object's
owner are never filled at any setting, and
""",
"""an LMV, HSM state, a linkea, an inode number and a class are never filled at
any setting, and
""")],
'lustre/utils/liblustreapi_scan.c': [
(""" * A hardlinked object has one pathname per link and the record is gathered
 * at the first, as llapi_scan_rec_path() returns it.  The MDT's order picks
""",
""" * A hardlinked object has one pathname per link and the record is gathered
 * at the first one fid2path returns.  The MDT's order picks
"""),
(""" * one that was asked for.  llapi_scan_rec_path() carries the same warning
 * and only formats a name; this one goes on to open and gather, so the
 * caller has more to lose by getting it wrong.
""",
""" * one that was asked for.  This call goes on to open and gather what it
 * resolved, so the caller has a lot to lose by getting it wrong.
"""),
(""" * name" as well as a bad argument, as it does for llapi_scan_rec_path();
""",
""" * name" as well as a bad argument;
"""),
("""	 * -EBADF and not -EINVAL, as llapi_scan_rec_path() answers for the
	 * same mistake: -EINVAL here also means "this FID has no name", so a
	 * consumer looping over a changelog with a mount it failed to open
	 * would count every object nameless and exit 0.
""",
"""	 * -EBADF and not -EINVAL: -EINVAL here also means "this FID has no
	 * name", so a consumer looping over a changelog with a mount it
	 * failed to open would count every object nameless and exit 0.
"""),
("""	 * mnt_path is not optional, as it is for llapi_scan_rec_path(): that
	 * call formats a name for the caller to read, this one opens it.  A
	 * filesystem-root-relative path would name whatever sits at the same
	 * place under / -- nothing, usually, but not always the nothing the
	 * caller would notice.
""",
"""	 * mnt_path is not optional: this call opens the name it builds.  A
	 * filesystem-root-relative path would name whatever sits at the same
	 * place under / -- nothing, usually, but not always the nothing the
	 * caller would notice.
"""),
],
'Documentation/man3/llapi_scan_fid.3': [
("""is open on mislabels the answer. That is
where this differs from
.BR llapi_scan_rec_path (3),
which formats a name for the caller to read rather than opening it. A caller
""",
"""is open on mislabels the answer. A caller
"""),
("""the first the MDT lists, as
.BR llapi_scan_rec_path (3)
returns it. The caller does not choose""",
"""the first the MDT lists. The caller does not choose"""),
("""because that one also means \\(lqthis FID has no name\\(rq; see
.BR llapi_scan_rec_path (3),
which answers the same way.
""",
"""because that one also means \\(lqthis FID has no name\\(rq.
"""),
(""".I this object has no name
as well as a bad argument, as
.BR llapi_scan_rec_path (3)
documents.
""",
""".I this object has no name
as well as a bad argument.
"""),
(""".BR llapi_scan_namespace (3),
.BR llapi_scan_rec_path (3),
.BR lustreapi (7)
""",
""".BR llapi_scan_namespace (3),
.BR lustreapi (7)
"""),
],
}
SUBJ417 = "LU-20650 lfs: add find --since, from the changelog"
MSG417 = ("""test means.  Its locals stay separate from the assignments that fill
them, and it sorts off the pipeline rather than in it:
""", """test means.  The locals that take an lfs find's output are declared
apart from the assignment, and it sorts off the pipeline rather than in
it:
""")
MISSES = []
def _apply(table, path, s):
    for o, n in table.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
def fn(path, s, subj):
    s = _apply(ALWAYS, path, s)
    if not HAS288:
        s = _apply(BELOW, path, s)
    # 8a0307fa: name the bits later changes take, while they are a gap
    if path == H and EVENT in s:
        gap = []
        if SHARD not in s:
            gap.append('0x0000800000000000 LU-20611')
        if OWNER not in s:
            gap.append('0x0001000000000000 LU-20637')
        if gap:
            s = s.replace(CLASS, CLASS + '/* reserved: %s */\n' % ', '.join(gap))
    return s
def msgfn(msg, subj):
    if subj == SUBJ417:
        assert MSG417[0] in msg, '417 msg anchor'
        msg = msg.replace(*MSG417)
    return msg
