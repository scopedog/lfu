# AI on 68288 PS30:
# 010bc2da: llapi_find_device.3 "What it prints" ignored fp_paths and
#   fp_fid2path_mnt.  Only where the page already has them (68288 up).
# 3592e59a: the pre-pass cannot tell a file it could not read from a
#   directory, so its warning must not say "pathnames below them".
MAN = 'Documentation/man3/llapi_find_device.3'
R = {
MAN: [(
""".B LLAPI_SCAN_F_INTERNAL
reaches those, so a default search prints the first form and nothing else.
Every record carries one or the other: the scan sets the object id on all
of them, so the second form always applies where the first does not.
""",
""".B LLAPI_SCAN_F_INTERNAL
reaches those, so a default search prints the first form and nothing else.
Every record carries one or the other: the scan sets the object id on all
of them, so the second form always applies where the first does not.
.I fp_paths
or
.I fp_fid2path_mnt
replaces both with a pathname: a match is then printed by name, or counted
as nameless and not printed (see NOTES).
""")],
'lustre/utils/liblustreapi_pfind.c': [(
"""	/* a directory the map lacks leaves everything below it nameless */
	if (rc == 0 && pre_skipped != 0)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "%s: %llu objects were skipped while mapping directories: pathnames below them may be missing",
""",
"""	/*
	 * A directory the map lacks leaves everything below it nameless.  An
	 * object it could not read has no known type, so it may not be one.
	 */
	if (rc == 0 && pre_skipped != 0)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "%s: %llu objects could not be read while mapping directories: any that were directories leave the pathnames below them missing",
""")],
}
def fn(path, s, subj):
    if path == MAN and 'fp_fid2path_mnt' not in s:
        return s
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
