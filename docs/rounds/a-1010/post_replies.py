#!/usr/bin/env python3
# Post the 10-10 replies into their threads, one call per change, on the
# patch set each root comment is on, so its line and range still fit.  Full comment ids, the
# root's range copied, line = end_line when ranged.  Usage: post_replies.py
# [--dry]
import json, subprocess, sys, urllib.request

DRY = '--dry' in sys.argv
# changes to post now; the rest wait for their own push
ONLY = {int(x) for x in sys.argv[1:] if x.isdigit()}
# (change, comment id, reply, resolved)
R = [
    (68415, '6ae9093e_b21df3b0', 'Done.', True),
    (68415, '950d74f6_d7985183', 'Done.', True),
    (68415, 'f88c505d_d8dd59e9',
     'Done. -ENOENT now counts as already cleared when the MDS still finds '
     'sc_user. A user registered without a mask or name cannot be looked up '
     'before LU-20647, so that case still fails; the page says so.', True),
    (68159, '2597ea78_75fe6c1a',
     'Done. -EINVAL first, as llapi_scan_device() gives.', True),
    (68159, '50166fe2_8aa0e69b',
     'Done. The bitmap is now read for the first worker and not at open '
     '(that part is in 68156), and the comment gives the real cost.', True),
    (68288, '39ffce91_7e9f1f98', 'Done.', True),
    (68288, '941f276d_46bf5f8c',
     'Done. The page says to allow about 1 KB per directory.', True),
    (68288, '22d5a676_6d6ae838', 'Done.', True),
    (68288, 'fe063eeb_0d54bfc4',
     'Not changed: style only, and the rename would touch most of the '
     'file.', True),
    (68417, '68ca454d_0f345470', 'Done.', True),
    (68417, '59a08d1c_ab5649a6',
     'lfs-find.1 and llapi_find_since.3 now say the window is measured on '
     'the MDS clock. No slack is added to the cut in this patch.', True),
    (68417, 'fa9800de_61888d7f',
     'Done. A failed object with no name under the search root is skipped '
     'and not counted.', True),
    (68418, 'ed0726f3_16587653', 'Done, in the comment and the message.',
     True),
    (68418, '9b7a96f7_5fa0df4d', 'Done.', True),
    (68418, 'a946ef6e_d22faf54',
     'Done. A record that carries a name is tested by find_prefilter() '
     'before the lookup.', True),
    (68419, '1cefe938_a28342ab',
     "Done. '! --changelog' and '! --resolve' are refused too, in 68418.",
     True),
]


def get(url):
    return json.loads(urllib.request.urlopen(url).read()[4:])


for change in sorted({r[0] for r in R}):
    if ONLY and change not in ONLY:
        continue
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
