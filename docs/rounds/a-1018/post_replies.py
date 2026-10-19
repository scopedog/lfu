#!/usr/bin/env python3
"""a-1018: post replies.md into the AI threads: one gerrit review call per change,
in_reply_to the FULL root id, resolved.  DRY=1 prints instead."""
import json, os, re, subprocess, sys, urllib.request
D = os.path.dirname(os.path.abspath(__file__))
rows = []
chg = None
for l in open(os.path.join(D, 'replies.md')):
    h = re.match(r'## (\d+)', l)
    if h:
        chg = int(h.group(1))
        continue
    m = re.match(r'- ([0-9a-f]{8}_[0-9a-f]{8}) [^:]*?:\s*(?:\S+ )?(?:[^\w]*)?(.*)$', l.rstrip())
    m = re.match(r'- ([0-9a-f]{8}_[0-9a-f]{8}) (?:\(#\d+\)|\S+(?: \S+)?)(?::| —) (.*)$', l.rstrip())
    if m and chg and not m.group(2).startswith('(no reply'):
        rows.append((chg, m.group(1), m.group(2).strip()))
by = {}
for n, cid, msg in rows:
    by.setdefault(n, []).append((cid, msg))
def get(url):
    return json.loads(urllib.request.urlopen(url).read().decode()[5:])
for n, items in sorted(by.items()):
    ps = get('https://review.whamcloud.com/changes/%d/detail?o=CURRENT_REVISION' % n)
    cur = list(ps['revisions'].values())[0]['_number']
    allc = get('https://review.whamcloud.com/changes/%d/comments' % n)
    byid = {c['id']: (path, c) for path, cs in allc.items() for c in cs}
    byps = {}
    for cid, msg in items:
        path, c = byid[cid]
        e = {'in_reply_to': cid, 'unresolved': False, 'message': msg}
        if 'line' in c:
            e['line'] = c['line']
        byps.setdefault(c['patch_set'], {}).setdefault(path, []).append(e)
    for ps_, comments in sorted(byps.items()):
        body = {'tag': 'review-reply', 'notify': 'OWNER', 'comments': comments}
        k = sum(len(v) for v in comments.values())
        print('%d PS%d (current %d): %d replies' % (n, ps_, cur, k))
        if os.environ.get('DRY'):
            continue
        r = subprocess.run(['ssh', '-p', '29418', 'hnishida@review.whamcloud.com',
                            'gerrit', 'review', '%d,%d' % (n, ps_), '--json'],
                           input=json.dumps(body), capture_output=True, text=True)
        print('   rc=%d %s' % (r.returncode, r.stderr.strip()[:200]))
