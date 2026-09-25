#!/bin/bash
D=/home/nishida/projects/lustre/lfu/docs/rounds/a-0925
python3 $D/xform4.py . >&2 || exit 1
msg=$(git log -1 --format=%B)
new=$(printf '%s\n' "$msg" | python3 $D/msg4.py) || exit 1
if ! git diff --quiet || [ "$new" != "$msg" ]; then
	git add -u
	printf '%s\n' "$new" | git commit -q --amend --no-verify -F - || exit 1
	echo "amended $(git log -1 --format='%h %s' | cut -c1-60)" >&2
fi
