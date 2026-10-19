#!/bin/bash
# 10-19 lab (host): pack the two arms and the scripts for the clone VM.
#   o = h1019-fork-1014 103aef57d1 (as pushed, a1018), n = fork-1014 (a-1019 fixes)
set -eu
F=~/lfs-fork-1014; H=$(cd $(dirname $0) && pwd)
for a in o:h1019-fork-1014 n:fork-1014; do
	n=${a%%:*}; c=$(git -C $F rev-parse --short=10 ${a#*:})
	git -C $F archive --format=tar.gz --prefix=x/ $c > /tmp/lab1019-$n.tgz
	echo $c > /tmp/lab1019-$n.sha
	echo "$n = $c"
done
scp -q /tmp/lab1019-{o,n}.tgz /tmp/lab1019-{o,n}.sha $H/*.sh $H/*.c nishida@192.168.122.10:/tmp/
