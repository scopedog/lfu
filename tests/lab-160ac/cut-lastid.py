# Put back what round 15 changed on the OST --fid2path path:
#   1. scan_classify() testing LMAC_FID_ON_OST before fid_is_last_id()
#   2. the no-name arm without -EINVAL
import sys
d = sys.argv[1]
p = d + '/lustre/utils/liblustreapi_scan_device.c'
s = open(p).read()
new = '''	if (fid_is_last_id(&lma->lma_self_fid))
		return LLAPI_SCAN_CLS_INTERNAL;
	if (lma->lma_compat & LMAC_FID_ON_OST)
		return LLAPI_SCAN_CLS_OST_OBJ;

	seq = lma->lma_self_fid.f_seq;
	if (fid_seq_is_idif(seq))
		return LLAPI_SCAN_CLS_OST_OBJ;
'''
old = '''	if (lma->lma_compat & LMAC_FID_ON_OST)
		return LLAPI_SCAN_CLS_OST_OBJ;

	seq = lma->lma_self_fid.f_seq;
	if (fid_seq_is_idif(seq))
		return LLAPI_SCAN_CLS_OST_OBJ;
	if (fid_is_last_id(&lma->lma_self_fid))
		return LLAPI_SCAN_CLS_INTERNAL;
'''
assert new in s, "the fixed order is not there"
s = s.replace(new, old, 1)
open(p, 'w').write(s)

p = d + '/lustre/utils/liblustreapi_pfind.c'
s = open(p).read()
new = '''		else if (prc == -ENOENT || prc == -ENODATA || prc == -EINVAL) {'''
old = '''		else if (prc == -ENOENT || prc == -ENODATA) {'''
assert new in s, "the -EINVAL arm is not there"
s = s.replace(new, old, 1)
open(p, 'w').write(s)
print("control arm cut in")
