# Messages for the test_300 split.
O156 = """conf-sanity test_300 checks the MDS version. It fails, not skips, if
the scanner is missing, because that is a broken install. It skips the
OST part for a ZFS, unreachable or older OST, and says so.
"""
N156 = """conf-sanity test_300a scans the MDT and test_300b the OST, each
checking its server's version. Each fails, not skips, if the scanner is
missing, because that is a broken install; 300b skips a ZFS,
unreachable or older OST rather than passing without scanning it.
"""
O160 = """that --internal only adds objects. Where mds1 and ost1 are one ldiskfs
node, it runs --local with --ost and with --mdt while the targets are
mounted, and checks that each reads only targets of that type.
"""
N160 = """that --internal only adds objects. test_300c runs --local with --ost
and with --mdt while the targets are mounted, and checks that each
reads only targets of that type; it skips unless mds1 and ost1 are one
ldiskfs node.
"""
def fn(path, s, subj):
    return s
def msgfn(m, subj):
    if subj.startswith('LU-20606 llapi: scan an ldiskfs target directly'):
        assert m.count(O156) == 1
        m = m.replace(O156, N156)
    elif subj.startswith('LU-20611 lfs: find over a target, with --device'):
        assert m.count(O160) == 1
        m = m.replace(O160, N160)
    return m
