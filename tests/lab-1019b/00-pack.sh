#!/bin/bash
# 10-19 lab b (host): pack the arms for #10 (160Ac DNE block).
#   a = 68419 07b1fc5ddd, t = fork-1014 tip 8afc606951,
#   x = t with one line broken in the cookie rewrite (built on the VM)
set -eu
F=~/lfs-fork-1014; H=$(cd $(dirname $0) && pwd)
for a in a:07b1fc5ddd t:fork-1014; do
	n=${a%%:*}; c=$(git -C $F rev-parse --short=10 ${a#*:})
	git -C $F archive --format=tar.gz --prefix=x/ $c > /tmp/lab1019b-$n.tgz
	echo $c > /tmp/lab1019b-$n.sha
	echo "$n = $c"
done
cp /tmp/lab1019b-t.tgz /tmp/lab1019b-x.tgz
echo "$(cat /tmp/lab1019b-t.sha)+broken" > /tmp/lab1019b-x.sha
scp -q /tmp/lab1019b-{a,t,x}.tgz /tmp/lab1019b-{a,t,x}.sha $H/0[1-9]*.sh nishida@192.168.122.10:/tmp/
