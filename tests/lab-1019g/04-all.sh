#!/bin/bash
# 10-20 lab g driver (root): every stage, results in one file.
R=/tmp/lab1019g-all.txt; : > $R
conf() { bash /tmp/02-conf.sh "$@"; echo "##### conf lib=$1 script=$2 tag=$3 ONLY=$4" >> $R; cat /tmp/lab1019g-conf-$3/run.txt >> $R; }
bash /tmp/03-ab.sh; echo "##### R6 A/B" >> $R; cat /tmp/lab1019g-ab/run.txt >> $R
conf t t t-300 "300a 300b 300c"
conf o t o-300c "300c"
echo "LAB 1019g DONE" >> $R
