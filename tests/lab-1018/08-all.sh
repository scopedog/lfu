#!/bin/bash
# 10-18 late lab driver (root): pass d (anchor-0 recheck warns, rc 0), arm g
# = fork-1014 26f7c0b1f6 only, A and B twice, then 160A* on g.
R=/tmp/lab1018-d.txt; : > $R
for t in g:g1 g:g2; do
	bash /tmp/06-recheck0.sh ${t%%:*} ${t#*:}
	echo "##### recheck0 ${t#*:}" >> $R; cat /tmp/lab1018-rc0-${t#*:}/run.txt >> $R
done
bash /tmp/02-sanity.sh g g g-160A "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "##### 160A* lib=g script=g" >> $R; cat /tmp/lab1018-sanity-g-160A/run.txt >> $R
echo "LAB 1018 D DONE" >> $R
