O = '\t\t      llapi_scan_cb_t cb, void *data);\n/* llapi_scan_changelog() flags, lfsc_flags */\n'
N = '\t\t      llapi_scan_cb_t cb, void *data);\n\n/* llapi_scan_changelog() flags, lfsc_flags */\n'
def fn(path, s, subj):
    return s.replace(O, N) if path == 'include/lustre/lustreapi.h' else s
