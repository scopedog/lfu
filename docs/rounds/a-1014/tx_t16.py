P = 'lustre/tests/llapi_scan_test.c'
O = '\t\t.lfsp_want = LLAPI_SCAN_FID | LLAPI_SCAN_UID | LLAPI_SCAN_LINKEA,\n'
N = '\t\t.lfsp_want = LLAPI_SCAN_FID | LLAPI_SCAN_UID |\n\t\t\t     LLAPI_SCAN_LINKEA,\n'
def fn(path, s, subj):
    return s.replace(O, N) if path == P else s
