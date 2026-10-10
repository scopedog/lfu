#!/bin/bash
# 10-10: lreview 68417 after the outside-subtree fix.
cd "$(dirname "$0")"
W=$HOME/lrv-1010-68417
git -C $HOME/lfs-fix-1007 worktree remove --force $W 2>/dev/null
git -C $HOME/lfs-fix-1007 worktree add -q --detach $W d4fb6de444 || exit 1
mkdir -p lreview-68417; (cd lreview-68417 && echo d4fb6de444 > shas.txt && lreview run --repo $W --last 1 > run.log 2>&1; echo "68417 rc=$?")
cp $HOME/projects/llm_code_and_review_tools/lreview-results/markdown/HEAD_d4fb6de_*.md lreview-68417/findings.md
git -C $HOME/lfs-fix-1007 worktree remove --force $W
echo LREVIEW2-DONE
