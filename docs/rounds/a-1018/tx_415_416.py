# AI on 68415 PS30 f5001c3d: the statx fields are reported in
#   lfsr_stx.stx_mask, not lfsr_valid (page, message, file header).
# AI on 68416 PS30 4d6e64ad: the message says nothing of test6's memset().
# AI on 68416 PS30 1360e218: -EACCES from the parent open is not in ERRORS.
CLMAN = 'Documentation/man3/llapi_scan_changelog.3'
CLC = 'lustre/utils/liblustreapi_scan_changelog.c'
FIDMAN = 'Documentation/man3/llapi_scan_fid.3'
R = {
CLMAN: [(
"""stripe or HSM state at any setting. Those fields arrive absent, with their
.I lfsr_valid
bit clear.
""",
"""stripe or HSM state at any setting. Those fields arrive absent, with their
bit clear: in
.I lfsr_stx.stx_mask
for the first six and in
.I lfsr_valid
for the rest, as
.BR llapi_scan_namespace (3)
describes.
"""), (
"""names a directory too. So
.B LLAPI_SCAN_TYPE
is set for those and clear for everything else.""",
"""names a directory too. So
.B LLAPI_SCAN_TYPE
.RB ( STATX_TYPE )
is set in
.I lfsr_stx.stx_mask
for those and clear for everything else.""")],
CLC: [(
""" * size, mode, times, layout or HSM state at any setting, so those are either
 * delivered absent, with their lfsr_valid bit clear, or filled by a lookup the
 * caller asked for with LLAPI_SCAN_CL_F_RESOLVE.  Resolution fills; it never
 * removes an object from the stream and never overrides what the event said.
""",
""" * size, mode, times, layout or HSM state at any setting, so those are either
 * delivered absent, with their bit clear (in lfsr_stx.stx_mask for the statx
 * fields, in lfsr_valid for the rest), or filled by a lookup the caller asked
 * for with LLAPI_SCAN_CL_F_RESOLVE.  Resolution fills; it never removes an
 * object from the stream and never overrides what the event said.
""")],
FIDMAN: [(
""".B -EPERM
the caller may not resolve FIDs; see
.BR llapi_fid2path_at (3).
""",
""".B -EPERM
the caller may not resolve FIDs; see
.BR llapi_fid2path_at (3).
.TP 15
.B -EACCES
the object, if it is a directory, or else its parent could not be opened for
reading. Only a caller without
.B CAP_DAC_READ_SEARCH
on a mount with
.B -o user_fid2path
meets this: the FID lookup itself checks no permission. A
.I lfsp_want
naming no field this call gathers opens nothing and is not affected.
""")],
}
S415 = "LU-20649 llapi: add llapi_scan_changelog()"
M415 = ("""state, so those fields are absent and their lfsr_valid bits are clear.
""", """state, so those fields are absent: their bits are clear in
lfsr_stx.stx_mask for the statx fields and in lfsr_valid for the rest.
""")
S416 = "LU-20650 llapi: fill a scan record for one FID"
M416 = ("""must fail and deliver no record whichever way it fails.

""", """must fail and deliver no record whichever way it fails.

test6 now zeroes its oversized parameter block with memset(): an
initialiser need not zero the bytes past .sp, and scan_param_copyin()
refuses non-zero ones.

""")
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
def msgfn(msg, subj):
    if subj == S415:
        assert M415[0] in msg, '415 msg anchor'
        msg = msg.replace(*M415)
    if subj == S416:
        assert M416[0] in msg, '416 msg anchor'
        msg = msg.replace(*M416)
    return msg
