#!/bin/bash
cd /usr/lib64/lustre/tests; export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > /tmp/t17-mount.txt 2>&1 || { echo mount failed; exit 1; }
for a in s4 s5; do
	echo "## $a"
	LD_LIBRARY_PATH=/tmp/arm1008$a/lib /tmp/lab1008-$a/lustre/tests/llapi_scan_test -d /mnt/lfst -t 17 2>&1 | tail -4
done
bash ./llmountcleanup.sh > /dev/null 2>&1
