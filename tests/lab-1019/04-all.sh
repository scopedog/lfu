#!/bin/bash
# 10-19 lab driver (root): every stage, results in one file.
R=/tmp/lab1019-all.txt; : > $R
bash /tmp/03-race.sh; echo "##### race + #6" >> $R; cat /tmp/lab1019-race/run.txt >> $R
bash /tmp/02-sanity.sh n n-sub "56Eea 157c 160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
echo "##### sanity subset arm=n" >> $R; cat /tmp/lab1019-sanity-n-sub/run.txt >> $R
echo "LAB 1019 DONE" >> $R
