#!/bin/bash
# 10-18 lab (root, clone VM): #21 by hand, old (o) vs new (n) on ONE fixture.
# Cookie written while the MDT log is empty; another changelog user (the
# only one, like Robinhood) then creates and clears records; next run.
set -u
OUT=/tmp/lab1018-cookie; rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') o=$(cat /tmp/lab1018-o.sha) n=$(cat /tmp/lab1018-n.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q " $M " || { echo "ABORT: no mount"; exit 4; }
for a in o n; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	echo "$a lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L/lfs | grep lustreapi | tr -s ' \t' ' ')"
done
U0=$(lctl --device lfst-MDT0000 changelog_register -n); U1=$(lctl --device lfst-MDT0001 changelog_register -n)
echo "other user: MDT0000 $U0, MDT0001 $U1"
clr() { lfs changelog_clear lfst-MDT0000 $U0 0; lfs changelog_clear lfst-MDT0001 $U1 0; }
D=$M/ck; lfs mkdir -i 0 $D; touch $D/before; sync; sleep 2; clr; sync; sleep 2
echo "-- log after clear: MDT0000 $(lfs changelog lfst-MDT0000 | wc -l) recs, MDT0001 $(lfs changelog lfst-MDT0001 | wc -l) recs"
for a in o n; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	out=$($L/lfs find $D --since-cookie /tmp/lab1018-ck.$a -type f 2>&1); rc=$?
	echo "-- run1 $a rc=$rc out=[$out]"; echo "   cookie $a:"; sed 's/^/     /' /tmp/lab1018-ck.$a
done
rm -f /tmp/lab1018-ck.o /tmp/lab1018-ck.n
for a in o n; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	$L/lfs find $D --since-cookie /tmp/lab1018-ck.$a -type f > /dev/null 2>&1
	echo "   rewrote cookie $a: $(grep -v '^#' /tmp/lab1018-ck.$a | tr '\n' ';')"
done
for i in 1 2 3 4 5; do touch $D/lost$i; done; sync; sleep 2
echo "-- before purge: MDT0000 $(lfs changelog lfst-MDT0000 | wc -l) recs, first $(lfs changelog lfst-MDT0000 | head -1 | cut -c1-60)"
clr; sync; sleep 2
touch $D/kept; sync; sleep 2
echo "-- after purge+kept: MDT0000 $(lfs changelog lfst-MDT0000 | tr '\n' '|' | cut -c1-200)"
for a in o n; do
	L=/tmp/lab1018-$a/lustre/utils/.libs
	cp /tmp/lab1018-ck.$a $OUT/ck2.$a
	out=$($L/lfs find $D --since-cookie $OUT/ck2.$a -type f 2>&1); rc=$?
	echo "-- run2 $a rc=$rc"; echo "$out" | sed 's/^/     /'
	echo "   cookie after: $(grep -v '^#' $OUT/ck2.$a | tr '\n' ';')"
done
lctl --device lfst-MDT0000 changelog_deregister $U0; lctl --device lfst-MDT0001 changelog_deregister $U1
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "COOKIE DONE"
