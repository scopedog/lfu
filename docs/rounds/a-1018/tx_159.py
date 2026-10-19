# AI on 68159 PS37:
# d55e3e04: find_check_lmm_info() is find_asks_layout() plus --projid;
#   build it from that rather than keep the list twice.
# 13021777: the kernel-doc said lfsp_got is overwritten; it is ignored and
#   the caller's is left untouched, as the man page says.
# 85bb9fc5: the growing-buffer sentence holds now that SCAN_LMV_BUF covers
#   XATTR_SIZE_MAX (tx_156); say where that limit is.
PF = 'lustre/utils/liblustreapi_pfind.c'
ASK = """/* the options only a layout answers; not --projid, which an OST has */
static bool find_asks_layout(const struct find_param *param)
{
	return param->fp_check_pool || param->fp_check_stripe_count ||
	       param->fp_check_stripe_size || param->fp_check_layout ||
	       param->fp_check_comp_count || param->fp_check_comp_end ||
	       param->fp_check_comp_start || param->fp_check_comp_flags ||
	       param->fp_check_mirror_count || param->fp_check_foreign ||
	       param->fp_check_mirror_state || param->fp_check_ext_size;
}

"""
LMM = """static bool find_check_lmm_info(struct find_param *param)
{
	return param->fp_check_pool || param->fp_check_stripe_count ||
	       param->fp_check_stripe_size || param->fp_check_layout ||
	       param->fp_check_comp_count || param->fp_check_comp_end ||
	       param->fp_check_comp_start || param->fp_check_comp_flags ||
	       param->fp_check_mirror_count || param->fp_check_foreign ||
	       param->fp_check_mirror_state || param->fp_check_ext_size ||
	       param->fp_check_projid;
}
"""
LMM_NEW = ASK + """static bool find_check_lmm_info(struct find_param *param)
{
	return find_asks_layout(param) || param->fp_check_projid;
}
"""
DOC = (""" * Four fields are the search's to decide and are overwritten whatever the
 * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,
 * lfsp_filter and lfsp_got.  lfsp_filter goes because this
""", """ * Three fields are the search's to decide and are set in its own copy
 * whatever the caller set: lfsp_want (the predicates decide it),
 * lfsp_thread_count and lfsp_filter.  lfsp_got is ignored, and the caller's
 * is left untouched.  lfsp_filter goes because this
""")
def fn(path, s, subj):
    if path != PF:
        return s
    if ASK in s:
        assert s.count(ASK) == 1 and s.count(LMM) == 1
        s = s.replace(ASK, '')
        s = s.replace(LMM, LMM_NEW)
        assert s.index('static bool find_asks_layout') < \
            s.index('static bool find_check_lmm_info')
    if DOC[0] in s:
        s = s.replace(*DOC)
    return s
S159 = "LU-20611 llapi: run find over a device scan"
M159 = ("""A foreign LMV larger than the search's buffer grows the buffer, as a
walk does, so --foreign and the other LMV checks still see it.
""", """A foreign LMV larger than the search's buffer grows the buffer, as a
walk does, so --foreign and the other LMV checks still see it. The
device scanner delivers one of up to XATTR_SIZE_MAX, the most an MDT
can store.
""")
def msgfn(msg, subj):
    if subj == S159:
        assert M159[0] in msg, '159 msg anchor'
        msg = msg.replace(*M159)
    return msg
