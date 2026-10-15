# Two lines my own reflows left over 80 columns.
R = {
'lustre/utils/lustreapi_internal.h': [(
""" * lfsc_mnt are dereferenced as strings.  Rounded down to the last whole field, as the parameter
 * struct above is, so a short size means "declared nothing from here on"
 * rather than "declared half a pointer".
""",
""" * lfsc_mnt are dereferenced as strings.  Rounded down to the last whole
 * field, as the parameter struct above is, so a short size means "declared
 * nothing from here on" rather than "declared half a pointer".
""")],
'lustre/utils/liblustreapi_pfind.c': [(
'\t\t/* the copies below are bounded: a longer one would be cut short */\n',
'\t\t/* the copies below are bounded: longer would be cut short */\n')],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
