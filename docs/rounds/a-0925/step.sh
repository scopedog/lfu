#!/bin/bash
# exec after every pick: apply the transform, amend if it changed anything,
# and fix 68157's message.  Never runs on a conflict stop (exec follows a pick).
X=/home/nishida/projects/lustre/lfu/docs/rounds/a-0925/xform.py

python3 $X . >&2 || exit 1
msg=$(git log -1 --format=%B)
new=$msg
if echo "$msg" | grep -q '^Change-Id: I6c1550b715bb505a3160c21bb68a0521c7a399da$'; then
	new=$(printf '%s\n' "$msg" | perl -0pe 's/The first changes\nwhat -printf prints:\n/The first changes\nwhat -printf prints; the second is documentation:\n/')
fi
if ! git diff --quiet || [ "$new" != "$msg" ]; then
	git add -u
	printf '%s\n' "$new" | git commit -q --amend --no-verify -F - || exit 1
	echo "amended $(git log -1 --format='%h %s' | cut -c1-60)" >&2
fi
