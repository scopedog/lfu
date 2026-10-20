#!/bin/bash
# 10-20 lab f (host): lreview r2 R9 + R11 (tx_1019f.py).
#   t = fork-1014 tip after tx_1019f, o = m1019-fork-1014 (before; control)
set -eu
F=~/lfs-fork-1014; H=$(cd $(dirname $0) && pwd)
for a in t:fork-1014 o:m1019-fork-1014; do
	n=${a%%:*}; c=$(git -C $F rev-parse --short=10 ${a#*:})
	git -C $F archive --format=tar.gz --prefix=x/ $c > /tmp/lab1019f-$n.tgz
	echo $c > /tmp/lab1019f-$n.sha
	echo "$n = $c"
done
scp -q /tmp/lab1019f-{t,o}.tgz /tmp/lab1019f-{t,o}.sha $H/0[1-9]*.sh nishida@192.168.122.10:/tmp/
