#!/bin/bash
# a-1019 (tx_1019f): build every rewritten commit: trunk from 68288 up, then the leaves above it.
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lfs-adl-1019
$S $T $(git -C $T rev-parse fork-1014~6) fork-1014
$S $T $(git -C $T merge-base fork-1014 fork-69502) fork-69502
$S $T $(git -C $T merge-base fork-1014 igif-1017) igif-1017
echo ALL-DONE
