#!/bin/bash
# 10-20 lab h driver (root): S4 held A/B (o n n o), then 160Aa-Af on t.
R=/tmp/lab1019h-all.txt; : > $R
for a in o:o1 n:n1 n:n2 o:o2; do
	bash /tmp/02-probe.sh ${a%%:*} ${a#*:}
	echo "##### probe arm=${a%%:*} tag=${a#*:}" >> $R; cat /tmp/lab1019h-probe-${a#*:}/run.txt >> $R
done
san() { bash /tmp/03-sanity.sh "$@"; echo "##### sanity arm=$1 tag=$2 MDSCOUNT=$3 ONLY=$4" >> $R; cat /tmp/lab1019h-sanity-$2/run.txt >> $R; }
san t t-160A1 1 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
san t t-160A2 2 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "LAB 1019h DONE" >> $R
