#!/usr/bin/env python3
# Post the 10-07 replies into their threads, one call per change, on the
# patch set each root comment is on, so its line and range still fit.  Full comment ids, the
# root's range copied, line = end_line when ranged.  Usage: post_replies.py
# [--dry]
import json, subprocess, sys, urllib.request

DRY = '--dry' in sys.argv
# (change, comment id, reply, resolved)
R = [
    (68159, 'c25be809_3bda963b', 'Done.', True),
    (68163, '963a5de4_b3355c0c', 'Done.', True),
    (68163, '81827f44_c98949dd',
     'Done. It tests lpc_open_access_error with geteuid() != 0 now.', True),
    (68415, 'a55b8afc_98fef952', 'Done.', True),
    (68415, 'f74c1dd9_631952dd',
     'Done. Only the moved object\'s record carries the source now; test8 checks it.',
     True),
    (68417, 'd740f535_b9571eee', 'Done.', True),
    (68417, 'd585a1a8_4477d9e7', 'Done.', True),
    (68418, '72ba260c_81b05286',
     '68420 rewrites this paragraph, with both points.', True),
    (68419, '23366946_40529039', 'Done.', True),
    (68419, 'ec958800_bb6abb23', 'Done.', True),
    (68419, 'b06c5a29_b66f78ff', 'Done.', True),
    (68419, '4ccc5b3a_616b761e',
     'Done. A symlink is refused (O_NOFOLLOW, lstat()).', True),
    (68419, 'd382f74a_a86d6760', 'Done.', True),
    (68419, 'c5256ba4_96b099bc',
     'Intended; the man pages say so now.', True),
    (68420, '9b919579_3ab48756', 'Done.', True),
    (68420, '62f06a34_5801f3dc', 'Done.', True),
    (68420, '9541f67b_3a4f8bad', 'Done.', True),
    (68420, 'cf7f229d_bc450d7e', 'Done.', True),
    (69443, 'eeae8a85_92242f5c', 'Done.', True),
    (69443, 'c877de12_e409591b', 'Done.', True),
    (69443, 'a3bd9728_fe489deb', 'Done. find_cookie_purged().', True),
]


def get(url):
    return json.loads(urllib.request.urlopen(url).read()[4:])


for change in sorted({r[0] for r in R}):
    roots = {}
    for path, cs in get('https://review.whamcloud.com/changes/%d/comments'
                        % change).items():
        for c in cs:
            roots[c['id']] = (path, c)
    byps = {}
    for (ch, cid, msg, resolved) in R:
        if ch != change:
            continue
        path, c = roots[cid]
        rep = {'in_reply_to': cid, 'message': msg,
               'unresolved': not resolved}
        if 'range' in c:
            rep['range'] = c['range']
            rep['line'] = c['range']['end_line']
        elif 'line' in c:
            rep['line'] = c['line']
        byps.setdefault(c['patch_set'], {}).setdefault(path, []).append(rep)
    for ps, comments in sorted(byps.items()):
        body = {'tag': 'review-reply', 'notify': 'OWNER',
                'comments': comments}
        print('%d,%d: %d replies' % (change, ps,
                                     sum(map(len, comments.values()))))
        if DRY:
            continue
        p = subprocess.run(['ssh', '-p', '29418',
                            'hnishida@review.whamcloud.com', 'gerrit',
                            'review', '%d,%d' % (change, ps), '--json'],
                           input=json.dumps(body).encode(),
                           capture_output=True)
        print('  rc=%d %s' % (p.returncode, p.stderr.decode().strip()[:200]))
