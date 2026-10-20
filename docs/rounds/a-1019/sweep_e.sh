#!/bin/bash
# a-1019 (tx_1019e): build every rewritten commit, trunk then each leaf from its parent.
# R is the ref prefix of the tips to sweep (refs/heads/: the real run, same shas as the dry one).
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lfs-adl-1019
R=${R:-refs/heads/}
mb() { git -C $T merge-base ${R}fork-1014 ${R}$1; }
$S $T master-1014 ${R}fork-1014
$S $T $(mb fork-69502) ${R}fork-69502
$S $T $(mb fork-69503) ${R}fork-69503
$S $T $(mb maxrate-1017) ${R}maxrate-1017
$S $T $(mb igif-1017) ${R}igif-1017
echo ALL-DONE
