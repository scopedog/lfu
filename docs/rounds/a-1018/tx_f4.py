# a1018 pass f4 (user, via coordinator): document, not fix, that an IGIF root
# is printed only with LLAPI_SCAN_F_INTERNAL / --internal.  Start: 69729
# 571df89aec (igif-1017 only).
FD = 'Documentation/man3/llapi_find_device.3'
LF = 'Documentation/man1/lfs-find.1'
HITS = {}
R = {
FD: [
('th', '.TH LLAPI_FIND_DEVICE 3 2026-10-15 ', '.TH LLAPI_FIND_DEVICE 3 2026-10-18 '),
('root', """printed as
.B /
(or as the mount with
.IR fp_fid2path_mnt ).
.LP
""", """printed as
.B /
(or as the mount with
.IR fp_fid2path_mnt ).
On a filesystem from before 2.4 the root has an IGIF and no linkea, so it
is printed only with
.B LLAPI_SCAN_F_INTERNAL
in
.I lfsp_flags
.RB ( "lfs find \\-\\-internal" ).
.LP
"""),
],
LF: [
('internal', """which are otherwise left out.
One with no FID is printed as obj:ID, its object number on the target.
""", """which are otherwise left out.
One with no FID is printed as obj:ID, its object number on the target.
On a filesystem from before 2.4 the root has no linkea and is counted
among them, so it is printed only with this option.
"""),
],
}
S = "LU-20637 llapi: find the root of an upgraded filesystem"
M = [("""root is not printed: it has no linkea, so the scan counts it as
internal.
""", """root is not printed: it has no linkea, so the scan counts it as
internal. llapi_find_device.3 and lfs-find.1 say so.
""")]
def fn(path, s, subj):
    for key, o, n in R.get(path, []):
        if o in s:
            assert s.count(o) == 1, (subj, key)
            s = s.replace(o, n)
            HITS.setdefault(subj, []).append(key)
    return s
def msgfn(msg, subj):
    if subj != S:
        return msg
    for o, n in M:
        assert o in msg, o[:40]
        msg = msg.replace(o, n)
        HITS.setdefault(subj, []).append('msg')
    return msg
import atexit, sys
@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
