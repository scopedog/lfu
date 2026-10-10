#!/bin/bash
# 10-10: lreview 68418 and 68419 after the '!' refusals, one at a time.
cd "$(dirname "$0")"
for pair in "68418b b297adfbdc" "68419 304aa3dda7"; do
	set -- $pair
	W=$HOME/lrv-1010-$1
	git -C $HOME/lfs-fix-1007 worktree remove --force $W 2>/dev/null
	git -C $HOME/lfs-fix-1007 worktree add -q --detach $W $2 || continue
	mkdir -p lreview-$1; (cd lreview-$1 && echo $2 > shas.txt && lreview run --repo $W --last 1 > run.log 2>&1; echo "$1 rc=$?")
	cp $HOME/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_${2:0:7}_*.md lreview-$1/findings.md
	git -C $HOME/lfs-fix-1007 worktree remove --force $W
done
echo LREVIEW4-DONE
