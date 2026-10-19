# a1018 pass f3 (69729 lreview nit): the root-loop comment serves every
# filesystem, not only an upgraded one.  Start: 69729 8c31e38c34.
SD = 'lustre/utils/liblustreapi_scan_device.c'
HITS = {}
O = "\t/* an IGIF root on a filesystem upgraded from before 2.4 */\n"
N = "\t/* .lustre's parent: an IGIF on a filesystem from before 2.4 */\n"
def fn(path, s, subj):
    if path == SD and O in s:
        assert s.count(O) == 1, subj
        s = s.replace(O, N)
        HITS.setdefault(subj, []).append('comment')
    return s
import atexit, sys
@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
