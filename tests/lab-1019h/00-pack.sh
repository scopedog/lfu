#!/bin/bash
# 10-20 lab h (host): 68419 S4, the restart probe's third read (tx_1019h.py).
#   o = 68419 before (o1019 0f9b013492), n = 68419 after (88ee77c068),
#   t = fork-1014 tip after tx_1019h (160A* on 1 and 2 MDTs)
set -eu
F=~/lfs-fork-1014; H=$(cd $(dirname $0) && pwd)
for a in o:0f9b013492 n:88ee77c068 t:fork-1014; do
	n=${a%%:*}; c=$(git -C $F rev-parse --short=10 ${a#*:})
	git -C $F archive --format=tar.gz --prefix=x/ $c > /tmp/lab1019h-$n.tgz
	echo $c > /tmp/lab1019h-$n.sha
	echo "$n = $c"
done
scp -q /tmp/lab1019h-{o,n,t}.tgz /tmp/lab1019h-{o,n,t}.sha $H/0[1-9]*.sh nishida@192.168.122.10:/tmp/
