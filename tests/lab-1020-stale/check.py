#!/usr/bin/python3
# A record is mixed when its FID (read at next()) and its link name (read
# later) belong to different files.  churn.py creates c<i> in order from one
# process, so within one sequence oid - i is the same for every true pair.
# Usage: check.py ringdump.out churn-dir-fid
import collections, sys
recs, dirfid = sys.argv[1], sys.argv[2].strip("[]")
dseq, doid = dirfid.split(":")[:2]
pairs = []
for line in open(recs):
    f = line.split()
    if len(f) < 4 or not f[2].startswith("c"):
        continue
    pseq, poid = f[3].split(":")
    if int(pseq, 16) != int(dseq, 16) or int(poid, 16) != int(doid, 16):
        continue
    seq, oid = f[0].split(":")[:2]
    pairs.append((seq, int(oid, 16) - int(f[2][1:]), f[0], f[2]))
mode = {}
for seq in set(p[0] for p in pairs):
    mode[seq] = collections.Counter(p[1] for p in pairs if p[0] == seq).most_common(1)[0][0]
bad = [p for p in pairs if p[1] != mode[p[0]]]
print("churn records %d mixed %d" % (len(pairs), len(bad)))
for p in bad[:10]:
    print("  MIXED fid %s name %s (delta %d, expected %d)" % (p[2], p[3], p[1], mode[p[0]]))
