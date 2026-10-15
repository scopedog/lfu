#!/bin/bash
# 10-15 lab (root, clone VM): lreview finding 1 on 69700 -- a stopped paced
# walk slept a slot for every entry it had not reached.  Build m2 (fixed
# 69700) and m3 (--max-rate on it), then test19 from m2 against the old
# library (m0) and the fixed one (m2), three times each; then all of
# llapi_scan_test and conf-sanity 300 on m2, conf-sanity 300a on m3.
set -u
O=/tmp/lab1015-stop; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
for a in m2 m3; do
	sudo -u nishida bash /tmp/07-build-nozfs.sh $a > $O/build-$a.txt 2>&1
	echo "$a ($(cat /tmp/lab1009-$a.sha)) build: $(tail -1 $O/build-$a.txt)"
	grep -q BUILD-OK $O/build-$a.txt || exit 3
done
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests; export PATH=/usr/lib64/lustre/tests:$PATH
export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
TB=/tmp/lab1009-m2/lustre/tests/.libs/llapi_scan_test
for arm in m0 m2; do
	for i in 1 2 3; do
		mkdir -p $M/t19
		LD_PRELOAD=/tmp/arm1009$arm/lib/liblustreapi.so.1 $TB -d $M/t19 -t 19 > $O/$arm-$i.txt 2>&1
		echo "$arm run $i: rc=$? $(grep -m1 -E 'took|test19' $O/$arm-$i.txt | cut -c1-140)"
		rm -rf $M/t19
	done
done
mkdir -p $M/all; LD_PRELOAD=/tmp/arm1009m2/lib/liblustreapi.so.1 $TB -d $M/all -p /tmp > $O/all.txt 2>&1
echo "all of llapi_scan_test on m2: rc=$?"; tail -2 $O/all.txt
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
unset MDSCOUNT OSTCOUNT FSNAME
bash /tmp/lab1015-conf.sh m2 /tmp/lab1009-m2/lustre/tests/conf-sanity.sh ldiskfs stop-m2 300
cat /tmp/lab1015-conf-stop-m2/run.txt; grep -E "test7 .*pace" /tmp/lab1015-conf-stop-m2/cs.txt | cut -c1-150
bash /tmp/lab1015-conf.sh m3 /tmp/lab1009-m3/lustre/tests/conf-sanity.sh ldiskfs stop-m3 300a
cat /tmp/lab1015-conf-stop-m3/run.txt; grep -E "objects at --max-rate" /tmp/lab1015-conf-stop-m3/cs.txt
echo "== end $(date '+%F %T')"
echo "STOP RUN DONE"
