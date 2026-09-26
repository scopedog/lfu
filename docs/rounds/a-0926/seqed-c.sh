#!/bin/bash
# after the 68288 fixup, replace its message
python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; out=[]; n=0
for l in open(p).read().split('\n'):
    out.append(l)
    if l.startswith('fixup') and l.endswith("name a device scan's objects"):
        out.append('exec git commit -q --amend --no-verify -F /home/nishida/projects/lustre/lfu/docs/rounds/a-0926/msg-68288-b.txt'); n+=1
assert n==1, n
open(p,'w').write('\n'.join(out))
PY
