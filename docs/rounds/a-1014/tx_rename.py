import re
F = 'endrec filter flags got max_cached mdtname min_age mnt padding size startrec stats type_mask user want'.split()
R = re.compile(r'\bsc_(' + '|'.join(F) + r')\b')
def fn(path, s, subj):
    if '/gss/' in path:
        return s
    return R.sub(r'lfsc_\1', s)
def msgfn(m, subj):
    return R.sub(r'lfsc_\1', m)
