#!/bin/bash
# 10-18 lab driver (root): every stage, results in one file.
R=/tmp/lab1018-all.txt; : > $R
bash /tmp/02-sanity.sh o n o-160Ac 160Ac;  echo "##### 160Ac lib=o script=n" >> $R; cat /tmp/lab1018-sanity-o-160Ac/run.txt >> $R
bash /tmp/02-sanity.sh n n n-160Ac 160Ac;  echo "##### 160Ac lib=n script=n" >> $R; cat /tmp/lab1018-sanity-n-160Ac/run.txt >> $R
bash /tmp/03-cookie.sh; echo "##### cookie hand-check" >> $R; cat /tmp/lab1018-cookie/run.txt >> $R
bash /tmp/02-sanity.sh n n n-160A "160Aa 160Ab 160Ac 160Ad 160Ae 160Af"; echo "##### 160A* lib=n" >> $R; cat /tmp/lab1018-sanity-n-160A/run.txt >> $R
bash /tmp/04-foreign.sh; echo "##### foreign" >> $R; cat /tmp/lab1018-foreign/run.txt >> $R
bash /tmp/02-sanity.sh m mf m-27K "27K 27Ke 27Kf"; echo "##### 27K lib=m script=mf" >> $R; cat /tmp/lab1018-sanity-m-27K/run.txt >> $R
bash /tmp/02-sanity.sh mf mf mf-27K "27K 27Ke 27Kf"; echo "##### 27K lib=mf script=mf" >> $R; cat /tmp/lab1018-sanity-mf-27K/run.txt >> $R
echo "LAB 1018 DONE" >> $R
