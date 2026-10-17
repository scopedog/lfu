# AI on 69502 PS8: 3c794599 imperative summary; 86500a8b the --changelog
# paragraph becomes a comment at the filter; 94da9534 the assignment sits
# with the other llapi_scan_param fields.
SUBJ = "LU-20650 lfs: find --since, pick before the gather"
R = {
'lustre/utils/liblustreapi_pfind.c': [(
"""	sp.lfsp_want = st->fss_want;

	st->fss_cb_called = false;
	sp.lfsp_filter = find_since_pre_cb;
	st->fss_matched = false;
""",
"""	sp.lfsp_want = st->fss_want;
	/* tests the live name: not for a source whose -name tests the
	 * name its record carried, such as --changelog
	 */
	sp.lfsp_filter = find_since_pre_cb;

	st->fss_cb_called = false;
	st->fss_matched = false;
""")],
}
MSG = [
("LU-20650 lfs: find --since, pick before the gather\n",
 "LU-20650 lfs: filter find --since candidates before the gather\n"),
("""
--changelog must not take this filter when it meets this change: -name
there tests the name the record carried, not the live one.
""", ""),
]
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
def msgfn(msg, subj):
    if subj == SUBJ:
        for o, n in MSG:
            assert o in msg, o[:30]
            msg = msg.replace(o, n, 1)
    return msg
