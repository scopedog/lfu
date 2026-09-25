#!/bin/bash
python3 /home/nishida/projects/lustre/lfu/docs/rounds/a-0925/xform3.py . >&2 || exit 1
if ! git diff --quiet; then
	git add -u
	git commit -q --amend --no-verify --no-edit || exit 1
	echo "amended $(git log -1 --format='%h %s' | cut -c1-60)" >&2
fi
