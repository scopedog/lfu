# AI on 68159 PS36 cc0ef9d2: LMV_SHARD must not widen to LMV.  The device
# scanner reads trusted.lmv for LMV_SHARD by itself (scan_want_xattr()); a
# namespace scan would pay the getattr + LMV ioctl on every object.
R = {
'lustre/utils/lustreapi_internal.h': [(
"""/* LMV_FOREIGN and LMV_SHARD are read from trusted.lmv, so both need LMV */
static inline __u64 scan_want_widen(__u64 want)
{
	if (want & (LLAPI_SCAN_LMV_FOREIGN | LLAPI_SCAN_LMV_SHARD))
""",
"""/*
 * LLAPI_SCAN_LMV_FOREIGN describes lfsr_lmv, so asking for it asks for that.
 * LLAPI_SCAN_LMV_SHARD does not: a shard has no lfsr_lmv, and the device
 * scanner reads trusted.lmv for it without LLAPI_SCAN_LMV.
 */
static inline __u64 scan_want_widen(__u64 want)
{
	if (want & LLAPI_SCAN_LMV_FOREIGN)
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
