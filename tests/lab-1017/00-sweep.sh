#!/bin/bash
# a1017: sweep the trunk, then each leaf from its parent; conf-sanity too
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lrv2-sweep
$S $T sweep/master-1014 sweep/fork-1014
$S $T sweep/fork-1014~4 sweep/fork-69502
$S $T $(git -C $T merge-base sweep/fork-1014 sweep/fork-69503) sweep/fork-69503
$S $T $(git -C $T merge-base sweep/fork-1014 sweep/fork-68726) sweep/fork-68726
for b in fork-1014 fork-69502 fork-69503 fork-68726; do
	git -C $T show sweep/$b:lustre/tests/conf-sanity.sh | bash -n &&
		echo "conf-sanity sh ok at $b"
done
echo ALL-DONE
