#!/bin/bash
# 10-19 lab c driver (root): every conf-sanity stage, results in one file.
R=/tmp/lab1019c-all.txt; : > $R
run() { bash /tmp/02-conf.sh "$@"; echo "##### lib=$1 script=$2 tag=$3 ONLY=$4" >> $R; cat /tmp/lab1019c-conf-$3/run.txt >> $R; }
run t t t-300 "300a 300b"
run c c c-300 "300a 300b"
run o t o-300 "300a 300b"
run t t t-300r "300a 300b"
echo "LAB 1019c DONE" >> $R
