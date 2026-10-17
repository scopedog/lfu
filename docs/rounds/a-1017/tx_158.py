# AI on 68158 PS34:
# 63979fe1: lfs_find_parse.c needs nothing from lustreapi_internal.h
#   until 68160 calls llapi_name_verify().
# 4441713a: lfs_find_parse_init() overwrites fp_min_depth/fp_quiet; say
#   what it sets, here and in the commit message.
SUBJ = "LU-20611 lfs: share find's predicate parsing"
R = {
'lustre/utils/lfs_find_parse.c': [(
"""#include "lstddef.h"
#include "lustreapi_internal.h"
""",
"""#include "lstddef.h"
""")],
'lustre/utils/lfs_find_parse.h': [(
""" * caller handing over a zeroed structure walks the top directory only and
 * dates it differently.  This sets those two, carries fp_min_depth and
 * fp_quiet as lfs_find() set them, and zeroes the rest, so a second front
 * end copies a call rather than an initialiser.
""",
""" * caller handing over a zeroed structure walks the top directory only and
 * compares "-mtime +1y" without its margin.  This sets fp_max_depth = -1
 * (no limit), fp_time_margin = FP_DEFAULT_TIME_MARGIN and fp_quiet = 1,
 * and zeroes the rest, so a second front end copies a call rather than an
 * initialiser.
""")],
}
MSG = [(
"""lfs_find_parse_init() prepares the structure. It sets fp_max_depth and
fp_time_margin, which must not be 0, keeps fp_min_depth and fp_quiet
as lfs_find() set them, and zeroes the rest. lfs_find_parse_fini()
frees the four find_param fields that a parse can allocate.""",
"""lfs_find_parse_init() prepares the structure. It sets fp_max_depth and
fp_time_margin, which must not be 0, sets fp_quiet, and zeroes the
rest. lfs_find_parse_fini() frees the four find_param fields that a
parse can allocate.""")]
def fn(path, s, subj):
    # 68160 brings the first use (llapi_name_verify()), and the include
    if path == 'lustre/utils/lfs_find_parse.c' and 'llapi_name_verify' in s:
        return s
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
def msgfn(msg, subj):
    if subj == SUBJ:
        for o, n in MSG:
            assert o in msg, 'msg anchor'
            msg = msg.replace(o, n)
    return msg
