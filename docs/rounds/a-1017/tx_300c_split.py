# AI on 68160 PS37 02a10a46: test_300c skipped wherever mds1 and ost1 are
# separate nodes, i.e. in every review session.  Each sweep now runs on its
# own facet; only the cross-type check needs the shared node.
import os
D = os.path.dirname(os.path.abspath(__file__))
OLD = open(os.path.join(D, '300c.old')).read()
NEW = open(os.path.join(D, '300c.new')).read()
def fn(path, s, subj):
    if path == 'lustre/tests/conf-sanity.sh' and OLD in s:
        s = s.replace(OLD, NEW)
    return s
