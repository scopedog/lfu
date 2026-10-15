# Move the changelog scanner's declarations (and llapi_scan_rec_path(), once
# 68288 adds it) from between llapi_fid2path() and llapi_path2fid() to just
# after llapi_scan_device(), beside the other scanners (lreview on 68415').
H = 'include/lustre/lustreapi.h'
START = '/* llapi_scan_changelog() flags, lfsc_flags */\n'
DECL = ('int llapi_scan_changelog(const struct llapi_scan_changelog_param *sc,\n'
        '\t\t\t llapi_scan_cb_t cb, void *data);\n')
RECP = ('\nint llapi_scan_rec_path(int mnt_fd, const char *mnt_path,\n'
        '\t\t\tconst struct llapi_scan_rec *rec,\n'
        '\t\t\tchar *buf, size_t buflen);\n')
DEV = ('int llapi_scan_device(const char *device, const struct llapi_scan_param *sp,\n'
       '\t\t      llapi_scan_cb_t cb, void *data);\n')
def fn(path, s, subj):
    if path != H or START not in s:
        return s
    assert s.count(START) == 1 and s.count(DECL) == 1 and s.count(DEV) == 1
    i = s.index(START)
    j = s.index(DECL) + len(DECL)
    if s.startswith(RECP, j):
        j += len(RECP)
    block = s[i:j]
    s = s[:i] + s[j:]
    k = s.index(DEV) + len(DEV)
    return s[:k] + block + '\n' + s[k:]
