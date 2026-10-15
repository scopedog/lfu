# lreview on 69502': name the wrapper, describe the right set of objects;
# and --changelog is no longer below this change after the fork.
O1 = "So --since now passes find_since_pick() as the filter. The filter\n"
N1 = ("So --since now passes find_since_pre_cb(), a wrapper around\n"
      "find_since_pick(), as the filter. The filter\n")
O2 = """The warnings can differ a little. The fid2path and the statx() still
run before the filter, so an object that has gone, or one under a
directory the caller cannot search, is counted as before. Only a
failure in the gather itself is no longer counted for an object
outside the subtree: an open of a parent the caller cannot read, or
the object changing after the statx(). --changelog is not changed:
-name there tests the name the record carried, not the live one.
"""
N2 = """The warnings can differ a little. The fid2path and the statx() still
run before the filter, so an object that has gone, or one under a
directory the caller cannot search, is counted as before. What changes
is an object inside the subtree that -name or -type rejects: a failure
in its gather -- an open of a parent the caller cannot read, or the
object changing after the statx() -- was counted and made the exit
status, and now it is not gathered at all, as a walk never gathers an
entry its pre-filter rejected. An object outside the subtree was not
counted before either.

--changelog must not take this filter when it meets this change: -name
there tests the name the record carried, not the live one.
"""
def fn(path, s, subj):
    return s
def msgfn(m, subj):
    if subj.startswith('LU-20650 lfs: find --since, pick before the gather'):
        for o, n in ((O1, N1), (O2, N2)):
            assert m.count(o) == 1, o[:30]
            m = m.replace(o, n)
    return m
