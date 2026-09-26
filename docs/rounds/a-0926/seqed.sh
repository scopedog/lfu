#!/bin/bash
# after 68160's pick and its fixup, replace the message
python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; L=open(p).read().split('\n'); out=[]; i=0
for j,l in enumerate(L):
    out.append(l)
    if l.startswith('fixup') and 'find over a target, with --device' in l:
        out.append('exec git commit -q --amend --no-verify -F /home/nishida/projects/lustre/lfu/docs/rounds/a-0926/msg-68160.txt')
open(p,'w').write('\n'.join(out))
PY
