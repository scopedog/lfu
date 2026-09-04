#!/usr/bin/env python3
"""Paired analysis of the alternating A/B.

Runs alternate pre,post,pre,post..., so each post has an adjacent pre that
saw almost the same machine state.  Comparing those pairs cancels the slow
drift that makes the aggregate medians disagree in sign; the median of the
paired deltas is the estimate, and the spread of those deltas is what says
whether it means anything.
"""
import sys, statistics as st

rows = []
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) < 7: continue
    rows.append((f[0], int(f[2]), float(f[6]), int(f[5])))

pre = [r for r in rows if r[0] == 'pre']
post = [r for r in rows if r[0] == 'post']
n = min(len(pre), len(post))
emit = pre[0][1]
print(f"pairs={n}  objects={emit:,}  "
      f"record: pre={pre[0][3]//emit}B post={post[0][3]//emit}B")

deltas = [100.0 * (post[i][2] - pre[i][2]) / pre[i][2] for i in range(n)]
ns = [1e9 * (post[i][2] - pre[i][2]) / emit for i in range(n)]
deltas.sort(); ns.sort()

def pct(v, p):
    return v[min(len(v) - 1, max(0, int(round(p * (len(v) - 1)))))]

print(f"paired delta (post - pre), % of pre CPU time:")
print(f"   median {st.median(deltas):+.2f}%   "
      f"IQR [{pct(deltas,.25):+.2f}%, {pct(deltas,.75):+.2f}%]   "
      f"range [{deltas[0]:+.2f}%, {deltas[-1]:+.2f}%]")
print(f"   per object: median {st.median(ns):+.1f} ns   "
      f"IQR [{pct(ns,.25):+.1f}, {pct(ns,.75):+.1f}] ns")
wins = sum(1 for d in deltas if d > 0)
print(f"   post slower in {wins}/{n} pairs "
      f"({100.0*wins/n:.0f}%; 50% = indistinguishable)")
# sign test: how surprising is that count if the two were identical?
from math import comb
p = sum(comb(n, k) for k in range(min(wins, n - wins) + 1)) / 2**n * 2
print(f"   sign test p = {p:.4f}"
      f"{'  (not significant)' if p > 0.05 else '  (significant)'}")
