#!/bin/bash
# 10-17 lab driver (root): every stage, results gathered in one file.
R=/tmp/lab1017-all.txt; : > $R
bash /tmp/04-ab.sh; cat /tmp/lab1017-ab/run.txt >> $R
sudo -u nishida bash /tmp/05-t14.sh 40; cat /tmp/lab1017-t14.txt >> $R
for fs in ldiskfs zfs; do
	bash /tmp/03-conf.sh n1 /tmp/lab1009-n1/lustre/tests/conf-sanity.sh $fs n1-$fs 300
	echo "##### conf n1 $fs" >> $R; cat /tmp/lab1017-conf-n1-$fs/run.txt >> $R
done
bash /tmp/02-sanity.sh n1 ldiskfs
echo "##### sanity n1 ldiskfs" >> $R; tail -12 /tmp/lab1009-n1-sanity-ldiskfs/run.txt >> $R
bash /tmp/02-sanity.sh n2 ldiskfs
echo "##### sanity n2 ldiskfs" >> $R; tail -12 /tmp/lab1009-n2-sanity-ldiskfs/run.txt >> $R
echo "LAB 1017 DONE" >> $R
