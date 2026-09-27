#!/bin/bash
# lreview each changed commit of the 09-27 round, ONE at a time.
cd /home/nishida/projects/lustre/lfu/docs/rounds/a-0927/lreview || exit 1
for pair in 68156:1bddb707ab 68157:66c7a6087c 68159:65bac8790e 68160:c44ad1ff63 \
	    68163:ed98d047c9 68288:e2281efb03 68415:b579f14d7a; do
	ch=${pair%%:*}; sha=${pair##*:}
	wt=$HOME/lrv0927-$ch
	[ -d $wt ] || git -C $HOME/lfs-artem-0924 worktree add -q --detach $wt $sha
	echo "=== $ch $sha start $(date +%T)"
	lreview run --repo $wt --last 1 > run-$ch.log 2>&1
	echo "=== $ch rc=$? end $(date +%T)"
done
echo LREVIEW-ALL-DONE
