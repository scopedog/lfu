# adilger on 68156 PS30 (lustre_fid.h): 2.4 is not "new"; reworded in the
# copy 68156 moved into the uapi header.
P = 'include/uapi/linux/lustre/lustre_fid.h'
O = """/*
 * For new FS (>= 2.4), the root FID will be changed to
 * [FID_SEQ_ROOT:1:0], for existing FS, (upgraded to 2.4),
 * the root FID will still be IGIF
 */
"""
N = """/*
 * A filesystem formatted at 2.4 or later has [FID_SEQ_ROOT:1:0] as its root
 * FID; one upgraded from before 2.4 keeps an IGIF root.
 */
"""
def fn(path, s, subj):
    return s.replace(O, N) if path == P else s
