#!/bin/bash
# after the 68288 and 68415 fixups, replace their messages
python3 - "$1" <<'PY'
import sys
D='/home/nishida/projects/lustre/lfu/docs/rounds/a-0926/'
m={"name a device scan's objects": 'msg-68288-b.txt',
   'add llapi_scan_changelog()': 'msg-68415-b.txt'}
p=sys.argv[1]; out=[]; n=0
for l in open(p).read().split('\n'):
    out.append(l)
    if l.startswith('fixup'):
        for k,f in m.items():
            if l.endswith(k):
                out.append('exec git commit -q --amend --no-verify -F '+D+f); n+=1
assert n==2, n
open(p,'w').write('\n'.join(out))
PY
