#!/bin/bash
# Does this MDT reuse a freed inode number at all, and how soon?  Two scans
# (no delay) during churn; inode numbers of churn files in each.
set -u
T=/tmp/stale-new; OUT=/tmp/stale-lab/probe; mkdir -p $OUT
export LUSTRE=$T/lustre FSTYPE=ldiskfs MDSCOUNT=1 OSTCOUNT=1 TMP=/tmp/stalefs
(cd $T/lustre/tests && NOFORMAT=1 bash llmount.sh) > $OUT/llmount.txt 2>&1
insmod $T/lustre/lfu/lfu.ko
gcc -O2 -I$T/include/uapi -o $T/ringdump /tmp/ringdump.c
d=/mnt/lustre/probe; rm -rf $d; mkdir $d
rm -f $OUT/stop; python3 /tmp/churn.py $d 200 $OUT/stop > $OUT/churn.out 2>&1 &
( while [ ! -e $OUT/stop ]; do echo 2 > /proc/sys/vm/drop_caches; sleep 0.2; done ) &
sleep 3
for r in 1 2 3; do
	$T/ringdump lustre-MDT0000 2>/dev/null | awk '$3 ~ /^c[0-9]+$/ {print $5, $3}' | sort -n > $OUT/r$r.txt
	sleep 2
done
touch $OUT/stop; wait
for r in 1 2 3; do
	echo "round $r: churn objs $(wc -l < $OUT/r$r.txt), ino range $(head -1 $OUT/r$r.txt | cut -d' ' -f1)-$(tail -1 $OUT/r$r.txt | cut -d' ' -f1), distinct ino $(cut -d' ' -f1 $OUT/r$r.txt | sort -u | wc -l)"
done
echo "inos seen in round 1 and again in round 3 under a different name: $(join $OUT/r1.txt $OUT/r3.txt | awk '$2 != $3' | wc -l) of $(join $OUT/r1.txt $OUT/r3.txt | wc -l) shared"
cat $OUT/churn.out
rmmod lfu; (cd $T/lustre/tests && bash llmountcleanup.sh) > $OUT/cleanup.txt 2>&1
