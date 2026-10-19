#!/bin/bash
# 10-18 pass f lab driver (root): #2's new anchor-0 warning wording on arm
# h = fork-1014 de3b3921a0 (06-recheck0.sh, A and B once), then 160A* on h.
R=/tmp/lab1018-f.txt; : > $R
bash /tmp/06-recheck0.sh h h1
echo "##### recheck0 h1" >> $R; cat /tmp/lab1018-rc0-h1/run.txt >> $R
bash /tmp/02-sanity.sh h h h-160A "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "##### 160A* lib=h script=h" >> $R; cat /tmp/lab1018-sanity-h-160A/run.txt >> $R
echo "LAB 1018 F DONE" >> $R
