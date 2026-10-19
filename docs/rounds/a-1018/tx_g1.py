# a1018 pass g1 (69443 lreview nit): "an MDT whose log was empty" is wider
# than the code; only an MDT anchored at 0 skips the recheck.  Start: 69443.
HITS = {}
R = {
    'Documentation/man1/lfs-find.1': (
        """records arrive; records made and purged during the run on an MDT whose log
was empty when it began; a purge during the run of an MDT that
""",
        """records arrive; records made and purged during the run on an MDT recorded
at 0 whose log was empty when it began; a purge during the run of an MDT that
"""),
    'Documentation/man3/llapi_find_since.3': (
        """arrive; records made and cleared during the call on an MDT whose log was
empty when it began; a clear during the call on an MDT the cookie has no
line for, as on a first call; and a clear on the MDT being read.
""",
        """arrive; records made and cleared during the call on an MDT anchored at 0
whose log was empty when it began; a clear during the call on an MDT the
cookie has no line for, as on a first call; and a clear on the MDT being
read.
"""),
}
MO = """made and purged during the run on an MDT whose log was empty when it
began, """
MN = """made and purged during the run on an MDT recorded at 0 whose log was
empty when it began, """
def fn(path, s, subj):
    if path in R and R[path][0] in s:
        assert s.count(R[path][0]) == 1, subj
        s = s.replace(R[path][0], R[path][1])
        HITS.setdefault(subj, []).append(path.split('/')[-1])
    return s
def msgfn(msg, subj):
    if MO in msg:
        msg = msg.replace(MO, MN)
        HITS.setdefault(subj, []).append('msg')
    return msg
import atexit, sys
@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
