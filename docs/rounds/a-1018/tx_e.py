# a1018 pass e: tx_d's new one-line comment was 81 columns.
PF = 'lustre/utils/liblustreapi_pfind.c'
def fn(path, s, subj):
    o = "\t/* as find_cookie_was_empty(): nothing to keep, so the cookie advances */\n"
    n = "\t/* as find_cookie_was_empty(): warn, and the cookie advances */\n"
    if path == PF and o in s:
        s = s.replace(o, n)
    return s
