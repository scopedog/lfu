#!/bin/bash
# Does every commit in the series build on its own?
#
# The cb_get_dirstripe() signature change sits at the BOTTOM of a 16-commit
# stack, and every caller above it has to move with it.  A tip that builds
# says nothing about that: the break would be in the middle, and only a
# bisect would find it -- which is exactly what upstream asks each patch to
# survive.  Builds lustre/utils only, which is where all the callers are.
set -e
L=${LTREE:-/home/nishida/lustre-160ac}
BASE=${BASE:-5afbab284e}
cd $L
git reset -q --hard HEAD; git clean -qfd
HEAD_WAS=$(git rev-parse HEAD)
fail=0
for c in $(git log --reverse --format=%h $BASE..$HEAD_WAS); do
	git checkout -q $c
	if make -j"$(nproc)" -C $L/lustre/utils > /tmp/bisect-$c.log 2>&1; then
		printf "  OK   %s %s\n" "$c" "$(git log -1 --format=%s $c | cut -c1-46)"
	else
		printf "  FAIL %s %s\n" "$c" "$(git log -1 --format=%s $c | cut -c1-46)"
		grep -m3 -E "error:" /tmp/bisect-$c.log | sed 's/^/         /'
		fail=1
	fi
done
git checkout -q $HEAD_WAS
echo "BISECT BUILD $([ $fail -eq 0 ] && echo CLEAN || echo BROKEN)"
