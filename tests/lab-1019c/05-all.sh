#!/bin/bash
# 10-19 lab c, second pass (root): t and c rebuilt with %LO in the -printf
# validator; negative controls for 300b; then the hand check.
R=/tmp/lab1019c-all2.txt; : > $R
run() { bash /tmp/02-conf.sh "$@"; echo "##### lib=$1 script=$2 tag=$3 ONLY=$4" >> $R; cat /tmp/lab1019c-conf-$3/run.txt >> $R; }
run t t t2-300 "300a 300b"
run c c c2-300 "300a 300b"
run o t o-300b "300b"
run c t ct-300b "300b"
bash /tmp/04-hand.sh; echo "##### hand" >> $R; cat /tmp/lab1019c-hand/run.txt >> $R
echo "LAB 1019c-2 DONE" >> $R
