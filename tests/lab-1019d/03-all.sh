#!/bin/bash
# 10-19 lab d driver (root): every stage, results in one file.
R=/tmp/lab1019d-all.txt; : > $R
san() { bash /tmp/02-sanity.sh "$@"; echo "##### sanity arm=$1 tag=$2 MDSCOUNT=$3 ONLY=$4" >> $R; cat /tmp/lab1019d-sanity-$2/run.txt >> $R; }
conf() { bash /tmp/02-conf.sh "$@"; echo "##### conf lib=$1 script=$2 tag=$3 ONLY=$4" >> $R; cat /tmp/lab1019d-conf-$3/run.txt >> $R; }
bash /tmp/04-l1.sh; echo "##### L1 A/B" >> $R; cat /tmp/lab1019d-l1/run.txt >> $R
bash /tmp/05-f2.sh; echo "##### F2/D1 hand" >> $R; cat /tmp/lab1019d-f2/run.txt >> $R
san t t-56E 1 "56Ea 56Eaa 56Eab 56Eb 56Ebb 56Ec 56Ed 56Eda 56Edb 56Ef 56Eg 56Eh 56Ei 56Ej 56Ek 56El 56Eea"
san t t-160A1 1 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
san t t-160A2 2 "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"
conf t t t-300 "300a 300b"
echo "LAB 1019d DONE" >> $R
