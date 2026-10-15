#!/bin/bash
# 10-15 lab (root, clone VM): 69700 with the 1 ms lag and the stop-latency
# doc (m4), --max-rate on it (m5).  test19 from m4 against the PS1 library
# (m0, must fail the stop timing) and m4, three times each; then all of
# llapi_scan_test and conf-sanity 300 on m4, conf-sanity 300a on m5.
set -u
O=/tmp/lab1015-lag; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
for a in m4 m5; do
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
TB=/tmp/lab1009-m4/lustre/tests/.libs/llapi_scan_test
for arm in m0 m4; do
	for i in 1 2 3; do
		mkdir -p $M/t19
		LD_PRELOAD=/tmp/arm1009$arm/lib/liblustreapi.so.1 $TB -d $M/t19 -t 19 > $O/$arm-$i.txt 2>&1
		echo "$arm run $i: rc=$? $(grep -m1 -E 'took|test19' $O/$arm-$i.txt | cut -c1-140)"
		rm -rf $M/t19
	done
done
mkdir -p $M/all; LD_PRELOAD=/tmp/arm1009m4/lib/liblustreapi.so.1 $TB -d $M/all -p /tmp > $O/all.txt 2>&1
echo "all of llapi_scan_test on m4: rc=$?"; tail -2 $O/all.txt
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
unset MDSCOUNT OSTCOUNT FSNAME
bash /tmp/lab1015-conf.sh m4 /tmp/lab1009-m4/lustre/tests/conf-sanity.sh ldiskfs stop-m4 300
cat /tmp/lab1015-conf-stop-m4/run.txt; grep -E "test7 .*pace" /tmp/lab1015-conf-stop-m4/cs.txt | cut -c1-150
bash /tmp/lab1015-conf.sh m5 /tmp/lab1009-m5/lustre/tests/conf-sanity.sh ldiskfs stop-m5 300a
cat /tmp/lab1015-conf-stop-m5/run.txt; grep -E "objects at --max-rate" /tmp/lab1015-conf-stop-m5/cs.txt
echo "== end $(date '+%F %T')"
echo "LAG RUN DONE"
