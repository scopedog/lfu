#!/bin/bash
# 10-19 lab b driver (root): every stage, results in one file.
R=/tmp/lab1019b-all.txt; : > $R
run() { bash /tmp/02-sanity.sh "$@"; echo "##### arm=$1 tag=$2 MDSCOUNT=$3 ONLY=$4" >> $R; cat /tmp/lab1019b-sanity-$2/run.txt >> $R; }
run t t-ac2 2 160Ac
run x x-ac2 2 160Ac
run a a-ac2 2 160Ac
run x x-ac2b 2 160Ac
run t t-ac2b 2 160Ac
run t t-all2 2 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
run t t-all1 1 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
run a a-ac1 1 160Ac
echo "LAB 1019b DONE" >> $R
