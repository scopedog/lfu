#!/bin/bash
# 10-10: lreview 68418 after the prefilter-before-lookup change.
cd "$(dirname "$0")"
W=$HOME/lrv-1010-68418
git -C $HOME/lfs-fix-1007 worktree remove --force $W 2>/dev/null
git -C $HOME/lfs-fix-1007 worktree add -q --detach $W 5ce62b3458 || exit 1
mkdir -p lreview-68418; (cd lreview-68418 && echo 5ce62b3458 > shas.txt && lreview run --repo $W --last 1 > run.log 2>&1; echo "68418 rc=$?")
cp $HOME/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_5ce62b3_*.md lreview-68418/findings.md
git -C $HOME/lfs-fix-1007 worktree remove --force $W
echo LREVIEW3-DONE
