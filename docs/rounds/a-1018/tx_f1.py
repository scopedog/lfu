# a1018 pass f1 (69700 PS3 AI 312cc898_63b63dd4): an object skipped before the
# pre-filter (torn or unreadable) is in ss_seen, so it takes a rate slot too.
# Start: 69700 4d35b0b1b0 (rate-1017, and 69728 above it).  fork-1014 has the
# same scan_sink_skip() text without sd_rate, so this must not start lower.
SD = 'lustre/utils/liblustreapi_scan_device.c'
HITS = {}
R = {SD: [
('dev', """static void scan_sink_skip(void *ctx, enum llapi_scan_skip why)
{
	struct scan_worker *w = ctx;
""", """static void scan_sink_skip(void *ctx, enum llapi_scan_skip why)
{
	struct scan_worker *w = ctx;
	struct scan_dev *dev = w->sw_dev;
"""),
('wait', """	if (why != LLAPI_SCAN_SKIP_XATTR)
		w->sw_stats.ss_seen++;
	w->sw_stats.ss_skipped++;
""", """	if (why != LLAPI_SCAN_SKIP_XATTR) {
		w->sw_stats.ss_seen++;
		/* it was read like any object, so it takes a rate slot */
		if (__atomic_load_n(&dev->sd_stop_rc, __ATOMIC_ACQUIRE) == 0)
			scan_rate_wait(&dev->sd_rate);
	}
	w->sw_stats.ss_skipped++;
"""),
]}
S = "LU-20606 llapi: limit a scan's rate"
M = [("""device scan counts it when it reads the inode or dnode, before
lfsp_filter, because that read happens either way.
""", """device scan counts it when it reads the inode or dnode, before
lfsp_filter, because that read happens either way. An object it skips
there, as torn or unreadable, takes a slot too.
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
