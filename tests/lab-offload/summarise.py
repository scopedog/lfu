import sys, statistics as st, collections as c
d = c.defaultdict(list); n = {}
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) != 4 or not p[0].startswith('/'): continue
    d[(p[0], p[1])].append(float(p[3])); n[(p[0], p[1])] = p[2]
for k, v in sorted(d.items()):
    m = st.median(v); spread = (max(v) - min(v)) / m * 100
    print(f"{k[0]:10s} {k[1]:10s} n={len(v)} count={n[k]:>6s} median={m:.3f}s  spread={spread:.0f}%")
