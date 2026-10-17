# AI on 69501 PS8 2019ab14: name the find_since_hardlinked() change.
SUBJ = "LU-20650 llapi: pass FID and nlink to llapi_scan_fid() filter"
O = """mask no gather runs, so it carries none. llapi_scan_test 17 checks
both.

"""
N = """mask no gather runs, so it carries none. llapi_scan_test 17 checks
both.

find_since_hardlinked() in liblustreapi_pfind.c takes a directory's
type from STATX_TYPE as well as STATX_MODE. Today's caller only sees
gathered records, which carry STATX_MODE; a filter given only the
type needs the other.

"""
def msgfn(msg, subj):
    if subj == SUBJ:
        assert O in msg
        msg = msg.replace(O, N)
    return msg
def fn(path, s, subj):
    return s
