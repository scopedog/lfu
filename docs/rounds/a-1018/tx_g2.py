# a1018 pass g2: rewrap the 69443 message paragraph g1 lengthened.
O = """empty when it began, a purge during the run of an MDT the cookie has no line for
(a first run), a purge on the MDT being read, which is the only window
on a single-MDT filesystem, and a record written late at the tail of a
busy log."""
N = """empty when it began, a purge during the run of an MDT the cookie has
no line for (a first run), a purge on the MDT being read, which is the
only window on a single-MDT filesystem, and a record written late at
the tail of a busy log."""
def fn(path, s, subj):
    return s
def msgfn(msg, subj):
    return msg.replace(O, N) if O in msg else msg
