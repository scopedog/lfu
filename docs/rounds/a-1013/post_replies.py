#!/usr/bin/env python3
# Post the 10-13 replies into their threads, one call per change, on the
# patch set each root comment is on, so its line and range still fit.  Full comment ids, the
# root's range copied, line = end_line when ranged.  Usage: post_replies.py
# [--dry]
import json, subprocess, sys, urllib.request

DRY = '--dry' in sys.argv
# changes to post now; the rest wait for their own push
ONLY = {int(x) for x in sys.argv[1:] if x.isdigit()}
# (change, comment id, reply, resolved)
R = [
    (68156, '376d68e6_4605c58b',
     'Done. The page and the kernel-doc now say that only an unreadable or '
     'plainly invalid object is skipped, and that another can give an '
     'inconsistent record.', True),
    (68156, '907d6e29_719ad93c', 'Done, in %description.', True),
    (68156, 'cd5b4613_b149dbdb', 'Done.', True),
    (68159, '95ee222e_01551aa7', 'Done.', True),
    (68159, '8916fd96_b9c45c0b',
     'Done. A scan now skips only the --foreign test for such a directory '
     'and applies the other predicates. It does not fall through to '
     'find_check_foreign(): that would reject every unstriped directory.',
     True),
    (68288, '8f88a2d2_ef901386', 'Done.', True),
    (68288, 'f3088c1f_47371b2b', 'Done.', True),
    (68415, '177f57f0_9c92ecd2', 'Done.', True),
    (68415, '91059706_f187cbe4',
     'Done. The scan stops clearing after the first failure.', True),
    (68416, 'bd08a29b_66d40182', 'Done.', True),
    (68416, '3d27afd4_4c146d50', 'Done.', True),
    (68416, 'c1f7f7c5_2216cc9c', 'Done.', True),
    (68416, '09644765_5919ffe2', 'Done.', True),
    (68417, '1f3b9901_12acaa7e',
     'Done, with a tab-indented continuation.', True),
    (68417, 'c6e8ee4f_64ebdd59',
     'Done. The first error is kept, the other MDTs are read, and it is '
     'returned at the end, unless fp_stop_on_error is set.', True),
    (68418, '1aeae682_17d3654c', 'Done.', True),
    (68419, '3a1ee14c_6a057b83', 'Done.', True),
    (68419, '9a24f3a7_8fa68a39', 'Done.', True),
    (68419, 'ba5a37ce_af079a72', 'Done.', True),
    (68420, '006804da_25e7d865', 'Done.', True),
    (68420, 'dbff52a1_654cb5b9',
     'Done. Both names are added, at index 1; the sign cases stay.', True),
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
