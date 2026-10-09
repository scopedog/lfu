#!/usr/bin/env python3
# Post the 10-08 replies into their threads, one call per change, on the
# patch set each root comment is on, so its line and range still fit.  Full comment ids, the
# root's range copied, line = end_line when ranged.  Usage: post_replies.py
# [--dry]
import json, subprocess, sys, urllib.request

DRY = '--dry' in sys.argv
# (change, comment id, reply, resolved)
R = [
    (68159, 'b609e81c_4c626663',
     'Done. An empty name now takes the torn-linkea path.', True),
    (68163, '91805ad6_be5bfa54', 'Done.', True),
    (68415, 'e89b731d_1f3019b2', 'Done.', True),
    (68415, '1ef16650_0b2ff779', 'Done.', True),
    (68415, 'ac3a6f27_8f07b059', 'Done.', True),
    (68417, 'a1c09353_42920310', 'Done.', True),
    (68417, '5538d83f_826a1c71',
     'Done: -EINVAL, for fp_changelog_mdt and fp_since_cookie too.', True),
    (68417, 'cdc038e8_0f90aadb', 'Done.', True),
    (68417, '7bb83a4f_6a0f084a', 'Done.', True),
    (68417, '7efd9bab_1892aea0', 'Done.', True),
    (68418, 'e601b13a_f9d4d449', 'Done.', True),
    (68419, 'c4dd5f3b_aaba6d0b', 'Done.', True),
    (68419, '2ca7425b_3f9336b4', 'Done.', True),
    (68420, 'e17fb28d_9d96d1b2',
     'Done, where "burst" first appears (68418).', True),
    (69443, 'f4af31b9_52a9d5f7', 'Done.', True),
    (69500, '608bbf64_c2246537', 'Done.', True),
    (69500, '33869de4_6135daec', 'Done.', True),
    (69501, 'fbce656d_82653553',
     'Done. The count is given for a directory too.', True),
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
