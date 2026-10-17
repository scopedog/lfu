# lreview of the a1017 commits, the findings taken:
# 68156 #1 / 68726: a union initialiser need not zero the tail (GCC 15);
#   memset the whole union, all three copies.
# 68158 #1: a zeroed fp_time_margin gives "+1y" a year's margin (my a1017
#   wording was wrong); #3: the helpers that change linkage.
# 68159 #1/#2: lfsp_got is left untouched, not zeroed or overwritten;
#   #3: llapi_layout_get_last_init_comp() returns the errno, sets none.
# 68160 #1: test_300c no longer skips on separate nodes.
# 68416 #1: the call's opens are MDS opens, logged as OPEN/CLOSE.
import re
INIT = '\t} big = { .sp = { .lfsp_size = sizeof(big) } };\n'
def union_fix(s):
    while INIT in s:
        i = s.index(INIT)
        s = s[:i] + '\t} big;\n' + s[i + len(INIT):]
        j = s.index('\n\n', i) + 1          # end of the declarations
        s = (s[:j] + '\n\t/* all of it: an initialiser need not zero buf\'s tail */\n'
             '\tmemset(&big, 0, sizeof(big));\n'
             '\tbig.sp.lfsp_size = sizeof(big);' + s[j:])
    return s
R = {
'lustre/utils/liblustreapi_pfind.c': [(
"""			if (path != NULL)
				llapi_error(LLAPI_MSG_ERROR, -errno,
					    "error: cannot get last initialized component\\n");""",
"""			if (path != NULL)
				llapi_error(LLAPI_MSG_ERROR, err,
					    "error: cannot get last initialized component\\n");""")],
'lustre/utils/lfs_find_parse.h': [(
""" * caller handing over a zeroed structure walks the top directory only and
 * compares "-mtime +1y" without its margin.  This sets fp_max_depth = -1
 * (no limit), fp_time_margin = FP_DEFAULT_TIME_MARGIN and fp_quiet = 1,
 * and zeroes the rest, so a second front end copies a call rather than an
 * initialiser.
""",
""" * caller handing over a zeroed structure walks the top directory only and
 * gives "-mtime +1y" a year's margin rather than the default.  This sets
 * fp_max_depth = -1 (no limit), fp_time_margin = FP_DEFAULT_TIME_MARGIN
 * and fp_quiet = 1, and zeroes the rest, so a second front end copies a
 * call rather than an initialiser.
""")],
'Documentation/man3/llapi_find_device.3': [(
"""as it does for a scan.  Four of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.IR lfsp_thread_count ,
.I lfsp_filter
and
.IR lfsp_got .
""",
"""as it does for a scan.  Three of its fields are the search's to decide and
are overwritten whatever the caller set:
.IR lfsp_want ,
.I lfsp_thread_count
and
.IR lfsp_filter .
""")],
'Documentation/man3/llapi_scan_fid.3': [(
"""The FID lookup is paid either way: a small buffer and one request to the
MDT per call.
""",
"""The FID lookup is paid either way: a small buffer and one request to the
MDT per call.
The opens are MDS opens, so with OPEN in the changelog mask each one is
logged: a consumer resolving its own changelog through this call reads
back the records its resolution wrote.
""")],
}
MSG = {
"LU-20611 lfs: share find's predicate parsing": [
("""callvpe.c. Nothing is exported from the library and no ABI changes.
""",
"""callvpe.c. Nothing is exported from the library and no ABI changes.
A second front end, lfs find over a target (LU-20611), parses the same
options.
"""),
("""The helpers move unchanged, except that the continuation line of the
set_time() prototype is re-indented. The loop moves with only these
differences:""",
"""The helpers move unchanged, except that the continuation line of the
set_time() prototype is re-indented, the ones lfs.c still calls lose
static, and xattr_match_info_append() and xattr_match_info_free()
become static. The loop moves with only these differences:"""),
],
"LU-20611 llapi: run find over a device scan": [
("""llapi_find_device() leaves lfsp_got zero: filled, it would report
find's own demand mask, not the caller's.
""",
"""llapi_find_device() leaves the caller's lfsp_got untouched: written,
it would report find's own demand mask, not the caller's.
"""),
],
"LU-20611 lfs: find over a target, with --device": [
("""test_300c runs --local with --ost
and with --mdt while the targets are mounted, and checks that each
reads only targets of that type; it skips unless mds1 and ost1 are one
ldiskfs node.
""",
"""test_300c runs --local with --ost
on ost1's node and with --mdt on mds1's while the targets are mounted,
and checks that each finds objects. Where mds1 and ost1 are one
ldiskfs node it also checks that each reads only targets of its type.
"""),
],
}
def fn(path, s, subj):
    if path in ('lustre/tests/llapi_scan_test.c',
                'lustre/tests/llapi_scan_device_test.c'):
        s = union_fix(s)
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
def msgfn(msg, subj):
    for o, n in MSG.get(subj, []):
        assert o in msg, subj + ': ' + o[:40]
        msg = msg.replace(o, n)
    return msg
