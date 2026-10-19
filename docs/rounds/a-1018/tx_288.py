# AI on 68288 PS31:
# 8ac62df6: llapi_scan_namespace.3 does not say it ignores lfsp_fsname.
# 9c17e029: llapi_scan_rec_path.3 names an OST object by lfsr_owner_fid,
#   which the record carries only when LLAPI_SCAN_OWNER was asked for.
# cf29a8b3 (user: take it): want_fsname duplicates spl.lfsp_fsname; the
#   scan reads it after the copyin, and llapi_find_device() sets it to the
#   mount's fsname.  scan_device_run() goes: its only caller was
#   llapi_scan_device().
NSMAN = 'Documentation/man3/llapi_scan_namespace.3'
RPMAN = 'Documentation/man3/llapi_scan_rec_path.3'
SD = 'lustre/utils/liblustreapi_scan_device.c'
IH = 'lustre/utils/lustreapi_internal.h'
PF = 'lustre/utils/liblustreapi_pfind.c'
R = {
NSMAN: [(
"""looks in to turn a target's name into a device, described on that page. A
namespace scan does not read it, being given a path rather than a target.
""",
"""looks in to turn a target's name into a device, described on that page. A
namespace scan does not read it, being given a path rather than a target.
.I lfsp_fsname
is read only by
.BR llapi_scan_device (3),
and is ignored here for the same reason.
""")],
RPMAN: [(
"""one belonging to a file created and never written, carry none. Otherwise its
FID resolves to the file that owns it.
""",
"""one belonging to a file created and never written, carry none. Otherwise it
is named by
.IR lfsr_owner_fid ,
the file that owns it, which the record carries only with
.B LLAPI_SCAN_OWNER
set in
.IR lfsr_valid :
ask for it in
.I lfsp_want
(or leave that 0). Without it an OST object returns this with no lookup.
""")],
SD: [(
"""	/*
	 * lfsp_fsname, not NULL: the check belongs to the scan because only the
	 * scan reads the target's label, and scan_device_run() copies sp in
	 * before it uses anything, so a short struct reads this as NULL.
	 */
	return scan_device_run(device, sp, cb, data,
			       sp != NULL &&
			       sp->lfsp_size >= (__u32)(offsetof(
					struct llapi_scan_param, lfsp_fsname) +
					sizeof(sp->lfsp_fsname)) ?
			       sp->lfsp_fsname : NULL);
}
""",
"""	return scan_device_run_prepass(device, sp, cb, data, NULL);
}
"""), (
""" * names as the consumer.  Lifted out of scan_device_run() so a pre-pass can
 * run before the search on the same open and the same workers -- opening a
 * target is not free, and on ZFS it is an import and an export.
""",
""" * names as the consumer.  Lifted out of scan_device_run_prepass() so a
 * pre-pass can run before the search on the same open and the same workers:
 * opening a target is not free, and on ZFS it is an import and an export.
"""), (
""" * @want_fsname, when not NULL, is the filesystem the caller is resolving
 * FIDs against; the scan refuses a target belonging to any other.  It is
""",
""" * lfsp_fsname, when not NULL, is the filesystem the caller is resolving
 * FIDs against; the scan refuses a target belonging to any other.  It is
"""), (
"""			    llapi_scan_cb_t cb, void *data,
			    const char *want_fsname,
			    const struct scan_prepass *pre)
{
""",
"""			    llapi_scan_cb_t cb, void *data,
			    const struct scan_prepass *pre)
{
"""), (
"""	if (want_fsname != NULL) {
		size_t flen = strlen(dev.sd_tgt_info.tt_label);
""",
"""	if (spl.lfsp_fsname != NULL) {
		const char *want_fsname = spl.lfsp_fsname;
		size_t flen = strlen(dev.sd_tgt_info.tt_label);
"""), (
"""
/* the same, for the callers with nothing to ask before their own pass */
int scan_device_run(const char *device, const struct llapi_scan_param *sp,
		    llapi_scan_cb_t cb, void *data, const char *want_fsname)
{
	return scan_device_run_prepass(device, sp, cb, data, want_fsname, NULL);
}
""",
"""""")],
IH: [(
"""/* the scan, plus the fsname a --fid2path mount must match; NULL leaves the
 * target unchecked.  llapi_scan_device() passes lfsp_fsname here.
 */
int scan_device_run(const char *device, const struct llapi_scan_param *sp,
		    llapi_scan_cb_t cb, void *data, const char *want_fsname);
/* the same, running @pre over the target first, on the same open */
int scan_device_run_prepass(const char *device,
			    const struct llapi_scan_param *sp,
			    llapi_scan_cb_t cb, void *data,
			    const char *want_fsname,
			    const struct scan_prepass *pre);
""",
"""/* the scan, running @pre (if not NULL) over the target first, on one open */
int scan_device_run_prepass(const char *device,
			    const struct llapi_scan_param *sp,
			    llapi_scan_cb_t cb, void *data,
			    const struct scan_prepass *pre);
""")],
PF: [(
"""	/*
	 * mfs is --fid2path's mount; lfsp_fsname is the caller's own answer,
	 * and the only one a --paths run has.  Without the fallback the
	 * -EXDEV this call documents could not fire for that caller.
	 */
	rc = scan_device_run_prepass(target, &spl, find_device_cb, &st,
				     mfs[0] != '\\0' ? mfs : spl.lfsp_fsname,
				     prep);
""",
"""	/*
	 * mfs is --fid2path's mount; otherwise lfsp_fsname is the caller's
	 * own answer, and the only one a --paths run has.
	 */
	if (mfs[0] != '\\0')
		spl.lfsp_fsname = mfs;
	rc = scan_device_run_prepass(target, &spl, find_device_cb, &st, prep);
""")],
}
S288 = "LU-20637 llapi: name a device scan's objects"
M288 = ("""lfsp_fsname gives a public caller the same check. llapi_scan_device()
passes it to the scan, and llapi_scan_rec_path.3 points callers to it.
""", """lfsp_fsname gives a public caller the same check, and lfs find sets it
from the mount, so the scan reads the name from one place.
llapi_scan_rec_path.3 points callers to it.
""")
HAS288 = False  # set by forktx3: lfsp_fsname exists from 68288 up
def fn(path, s, subj):
    if not HAS288:
        return s
    for o, n in R.get(path, []):
        if o in s:
            assert s.count(o) == 1, (path, o[:40])
            s = s.replace(o, n)
    return s
def msgfn(msg, subj):
    if subj == S288:
        assert M288[0] in msg, '288 msg anchor'
        msg = msg.replace(*M288)
    return msg
