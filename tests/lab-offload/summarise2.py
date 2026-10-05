import sys, statistics as st, collections as c
d = c.defaultdict(list)
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) == 4 and p[0].startswith('/') and p[1] in 'AB':
        d[(p[0], p[2], p[1])].append(float(p[3]))
for k in sorted(d):
    v = d[k]; m = st.median(v)
    print(f"{k[0]:10s} {k[1]} {k[2]} n={len(v)} median={m:.3f}s range={min(v):.3f}-{max(v):.3f}")
