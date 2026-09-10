#!/usr/bin/env python3
"""Median, range and spread per scope x arm from benchsub.sh output, plus the
ratios that matter.  Counts are checked constant within an arm: a run whose
count differs from its siblings is reported, not averaged in."""
import sys, statistics
from collections import defaultdict, OrderedDict

rows = defaultdict(list)
counts = defaultdict(set)
scopes = OrderedDict()
for line in open(sys.argv[1]):
    if line.startswith('#') or not line.strip():
        continue
    f = line.split()
    scope, arm, count, wall = f[0], f[1], f[2], float(f[3])
    scopes[scope] = True
    rows[(scope, arm)].append(wall)
    counts[(scope, arm)].add(count)

def med(scope, arm):
    return statistics.median(rows[(scope, arm)])

print(f"{'scope':24} {'arm':6} {'n':>2} {'count':>7} {'median':>8} {'range':>17} {'spread':>7}")
for scope in scopes:
    for arm in ('stock', 'ns', 'ns1', 'ns4', 'ns8', 'mount'):
        w = rows.get((scope, arm))
        if not w:
            continue
        m = statistics.median(w)
        half = (max(w) - min(w)) / 2 / m * 100
        c = ','.join(sorted(counts[(scope, arm)]))
        flag = '' if len(counts[(scope, arm)]) == 1 else '  COUNT VARIES'
        print(f"{scope:24} {arm:6} {len(w):2} {c:>7} {m:8.3f} {min(w):8.3f}-{max(w):<8.3f} +-{half:4.1f}%{flag}")
print()
root = next(iter(scopes))
print(f"{'scope':24} {'stock/offload':>13} {'walk/offload':>13} {'offload vs root offload':>24}")
for scope in scopes:
    try:
        so = med(scope, 'stock') / med(scope, 'mount')
        wo = med(scope, 'ns') / med(scope, 'mount')
        vr = med(scope, 'mount') / med(root, 'mount')
        print(f"{scope:24} {so:12.1f}x {wo:12.1f}x {vr:23.2f}x")
    except (KeyError, statistics.StatisticsError):
        pass
