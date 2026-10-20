#!/bin/bash
# a-1019 (tx_1019g): build every rewritten commit: trunk from 68160 up, then each leaf above its fork point.
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lfs-sweep-1020
$S $T 47d5221ea5 fork-1014
for b in fork-69501 fork-69502 fork-69503 rate-1017 maxrate-1017 igif-1017; do
	$S $T $(git -C $T merge-base fork-1014 $b) $b
done
echo ALL-DONE
