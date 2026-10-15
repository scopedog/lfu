# lreview on 68417': the filter comment's reason, and rc set before the
# message that reports it.
import re
P = 'lustre/utils/liblustreapi_pfind.c'
C1O = """ * It is asked here rather than in the callback because lfsc_filter sees each
 * delivery before any lookup, and the callback does not: an object already
 * printed is dropped before the lookup.
"""
C1N = """ * It is asked in lfsc_filter rather than in the callback.  Either runs
 * before the lookup, but a cut made here is counted in ss_filtered, with the
 * stream's own statistics.
"""
C2O = """	 * Refused here and not in the callback, so a burst from before the
	 * window is never looked up: it would print an object that has not
	 * changed inside it.
"""
C2N = """	 * A burst from before the window is refused before any lookup: looked
	 * up, it would print an object that has not changed inside it.
"""
PAT = re.compile(r'(\t+)llapi_error\(LLAPI_MSG_ERROR \| LLAPI_MSG_NO_ERRNO, 0,\n'
                 r'((?:[^;]|\n)*?\);)\n\1rc = (-E[A-Z]+);\n')
def fn(path, s, subj):
    if path != P:
        return s
    s = s.replace(C1O, C1N).replace(C2O, C2N)
    return PAT.sub(lambda m: f'{m.group(1)}rc = {m.group(3)};\n'
                   f'{m.group(1)}llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, rc,\n'
                   f'{m.group(2)}\n', s)
