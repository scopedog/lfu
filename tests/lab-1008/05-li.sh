#!/bin/bash
# lab: %Li/%Lo for an unstriped dir on MDT1, walk vs --since vs --changelog --resolve
set -u
T=/tmp/lab1008-new; L=$T/lustre/utils/.libs/lfs
export LD_LIBRARY_PATH=/tmp/arm1008new/lib
cd /usr/lib64/lustre/tests; export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > /tmp/li-mount.txt 2>&1 || { echo mount failed; exit 1; }
M=/mnt/lfst
lctl --device lfst-MDT0000 changelog_register -n > /dev/null; lctl --device lfst-MDT0001 changelog_register -n >/dev/null
$L mkdir -i 1 $M/d1; $L mkdir -i 0 $M/d0; touch $M/d1/f
sleep 2
echo "walk:";     $L find $M -maxdepth 1 -type d -printf '%p %Li %Lo\n'
echo "since:";    $L find $M --since 1h -type d -printf '%p %Li %Lo\n'
echo "changelog1:"; $L find $M --changelog lfst-MDT0001 --resolve -type d -printf '%p %Li %Lo\n'
bash ./llmountcleanup.sh > /dev/null 2>&1; echo cleanup=$?
