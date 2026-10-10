#!/bin/bash
# 10-10: lreview the three commits whose code changed, one at a time.
cd "$(dirname "$0")"
for pair in "68415 4f1d0dfee3" "68159 1abfebbd8c" "68156 99bcc55582"; do
	set -- $pair
	W=$HOME/lrv-1010-$1
	git -C $HOME/lfs-fix-1007 worktree remove --force $W 2>/dev/null
	git -C $HOME/lfs-fix-1007 worktree add -q --detach $W $2 || continue
	mkdir -p lreview-$1; (cd lreview-$1 && echo $2 > shas.txt && lreview run --repo $W --last 1 > run.log 2>&1; echo "$1 rc=$?")
	git -C $HOME/lfs-fix-1007 worktree remove --force $W
done
echo LREVIEW-ALL-DONE
