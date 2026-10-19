#!/bin/bash
# a1018: build every rewritten commit, trunk then each leaf from its parent.
# libscan_ldiskfs.c is not in the configured utils build, so it is compiled
# by hand at each commit too (#1 changed it).
S=/home/nishida/projects/lustre/lfu/tests/build-sweep-range.sh
T=~/lrv2-sweep
F=~/lfs-fork-1014
ld() {
	for c in $(git -C $T rev-list --reverse $1..$2); do
		git -C $T checkout -q --detach $c
		(cd $T && gcc -c -O2 -Wall -Werror -fPIC -D_GNU_SOURCE \
			-include config.h -Iinclude -Iinclude/uapi -Ilustre/utils \
			-o /dev/null lustre/utils/libscan_ldiskfs.c) &&
			echo "$(git -C $T rev-parse --short $c) ldiskfs=0" ||
			echo "$(git -C $T rev-parse --short $c) ldiskfs=FAIL"
	done
}
$S $T master-1014 fork-1014
$S $T fork-1014~3 fork-69502
$S $T $(git -C $T merge-base fork-1014 fork-69503) fork-69503
$S $T $(git -C $T merge-base fork-1014 rate-1017) maxrate-1017
$S $T $(git -C $T merge-base fork-1014 igif-1017) igif-1017
ld master-1014 fork-1014
ld fork-1014~3 fork-69502
ld $(git -C $T merge-base fork-1014 fork-69503) fork-69503
ld $(git -C $T merge-base fork-1014 rate-1017) maxrate-1017
ld $(git -C $T merge-base fork-1014 igif-1017) igif-1017
for b in fork-1014 fork-69502 fork-69503 maxrate-1017 igif-1017; do
	git -C $T show $b:lustre/tests/conf-sanity.sh | bash -n &&
		echo "conf-sanity sh ok at $b"
done
echo ALL-DONE
