#!/bin/bash
# 10-18 pm lab driver (root): fix #1 A/B alternated n f f n, then 160A* on f.
R=/tmp/lab1018-pm.txt; : > $R
for t in n:n1 f:f1 f:f2 n:n2; do
	bash /tmp/06-recheck0.sh ${t%%:*} ${t#*:}
	echo "##### recheck0 ${t#*:}" >> $R; cat /tmp/lab1018-rc0-${t#*:}/run.txt >> $R
done
bash /tmp/02-sanity.sh f f f-160A "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "##### 160A* lib=f script=f" >> $R; cat /tmp/lab1018-sanity-f-160A/run.txt >> $R
echo "LAB 1018 PM DONE" >> $R
