# a1018 pass c: two wording fixes in 69443 after re-reading pass b.
LF = 'Documentation/man1/lfs-find.1'
def fn(path, s, subj):
    o = "is removed, or warned for an MDT recorded at 0. Not caught: a purge that\n"
    n = "is removed; one recorded at 0 is warned of. Not caught: a purge that\n"
    if path == LF and o in s:
        s = s.replace(o, n)
    return s
S = "LU-20650 lfs: find --since-cookie, check each MDT when read"
def msgfn(msg, subj):
    o = """pre-pass keeps the oldest record it saw there, and any change in it
by then, an emptied log included, stops the run the same way.
"""
    n = """pre-pass keeps the oldest record it saw there, and any change in it
before that MDT is read, an emptied log included, stops the run the
same way.
"""
    if subj == S:
        assert o in msg
        msg = msg.replace(o, n)
    return msg
