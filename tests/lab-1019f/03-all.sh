#!/bin/bash
# 10-20 lab f driver (root): R11 A/B, then 160Aa-Af on the new tip.
R=/tmp/lab1019f-all.txt; : > $R
san() { bash /tmp/02-sanity.sh "$@"; echo "##### sanity arm=$1 tag=$2 MDSCOUNT=$3 ONLY=$4" >> $R; cat /tmp/lab1019f-sanity-$2/run.txt >> $R; }
san t t-160A1 1 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
san t t-160A2 2 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "LAB 1019f DONE" >> $R
