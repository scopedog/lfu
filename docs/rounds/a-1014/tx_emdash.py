# adilger on 68156 PS30: "far too many AI-generated em-dashes in the man
# pages".  The rewrites were made on each page as it stands at the tip (and
# llapi_scan_next.3 at 68726'); every changed passage, with two lines of
# context, replaces the same passage in any tree that holds it once.
import difflib, os
EM = '/tmp/claude-1004/-home-nishida-projects-lustre-lfu/b3736538-c7fe-4fa3-bd7f-c18e5e3ed3e8/scratchpad/em'
PAGES = {'lfs-find.1': 'Documentation/man1/lfs-find.1'}
for f in os.listdir(EM + '/new'):
    if f != 'lfs-find.1':
        PAGES[f] = 'Documentation/man3/' + f
MAP = {}
for f, path in PAGES.items():
    a = open(f'{EM}/orig/{f}').read().splitlines(True)
    b = open(f'{EM}/new/{f}').read().splitlines(True)
    reps = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == 'equal':
            continue
        lo, hi = max(0, i1 - 2), min(len(a), i2 + 2)
        old = ''.join(a[lo:hi])
        new = ''.join(a[lo:i1]) + ''.join(b[j1:j2]) + ''.join(a[i2:hi])
        reps.append((old, new))
    MAP[path] = reps
def fn(path, s, subj):
    for old, new in MAP.get(path, []):
        if s.count(old) == 1:
            s = s.replace(old, new)
    return s
