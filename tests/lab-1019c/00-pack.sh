#!/bin/bash
# 10-19 lab c (host): adilger's 68156 comments (tx_1019c.py).
#   t = fork-1014 tip, c = 68160 (lfs find --device, %LO without the owner),
#   o = j1019-fork-1014, the tip before tx_1019c (negative control)
set -eu
F=~/lfs-fork-1014; H=$(cd $(dirname $0) && pwd)
C160=$(git -C $F log --format=%h --grep=Ib25109943ad40afbc2d272a65e70c364c376b2b7 master-1014..fork-1014)
for a in t:fork-1014 c:$C160 o:j1019-fork-1014; do
	n=${a%%:*}; c=$(git -C $F rev-parse --short=10 ${a#*:})
	git -C $F archive --format=tar.gz --prefix=x/ $c > /tmp/lab1019c-$n.tgz
	echo $c > /tmp/lab1019c-$n.sha
	echo "$n = $c"
done
scp -q /tmp/lab1019c-{t,c,o}.tgz /tmp/lab1019c-{t,c,o}.sha $H/0[1-9]*.sh nishida@192.168.122.10:/tmp/
