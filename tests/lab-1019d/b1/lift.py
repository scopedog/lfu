import re,sys
d=sys.argv[1]
def grab(src, sig):
    s=open(src).read()
    i=s.index(sig); j=s.index('\n}\n', i)+3
    return s[i:j]
new=grab(d+'/new.c','static void scan_idif_set_index(')
k1=grab(d+'/kfid.h','static inline int ostid_set_id(')
k2=grab(d+'/kfid.h','static inline int fid_to_ostid(')
# the old sink: the raw self FID, as assigned
old=open(d+'/old.c').read()
assert 'rec.lfsr_fid = lma.lma_self_fid;\n\t\tif (fid_is_sane(&rec.lfsr_fid))' in old
assert 'scan_idif_set_index' not in old
open(d+'/lifted.h','w').write(new+'\n'+k1+'\n'+k2+'\n')
