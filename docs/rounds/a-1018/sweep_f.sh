#!/bin/bash
# a1018 pass f: build each rewritten commit (69700, 69728; 69443, 69500; 69729).
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lrv2-sweep
$S $T rate-1017~1 maxrate-1017
$S $T fork-1014~2 fork-1014
$S $T igif-1017~1 igif-1017
echo ALL-DONE
