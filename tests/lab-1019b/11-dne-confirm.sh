#!/bin/bash
# 10-19 lab B/#10 (root, clone VM): does a cookie run that reads one MDT
# keep the other MDT's line?  Arm n = fork-1014 ce898ad309 (/tmp/lab1019-n).
set -u
OUT=/tmp/lab1019b-dne; rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') n=$(cat /tmp/lab1019-n.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
mount -t lustre | grep -q " $M " || { echo "ABORT: no mount"; exit 4; }
L=/tmp/lab1019-n/lustre/utils/.libs/lfs
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L | grep lustreapi | tr -s ' \t' ' ')"
for m in 0 1; do lctl --device lfst-MDT000$m changelog_register; lctl set_param -n mdd.lfst-MDT000$m.changelog_mask=CREAT; done
D=$M/dne; CK=/root/ck.dne; rm -f $CK
$L mkdir -i 0 $D; $L mkdir -i 1 $D/m1
echo "m1 on MDT $($L getstripe -m $D/m1)"
sync; sleep 2
show() { echo "  rc=$1 out=[$(sed "s|$D/||g" $OUT/o | xargs)]"; echo "  cookie: $(tr '\n' ';' < $CK)"; }
echo "-- run1 (first, path)"; $L find $D --since-cookie $CK -type f > $OUT/o 2>&1; show $?
touch $D/m1/d1; sync; sleep 2
echo "-- run2 (path) after m1/d1"; $L find $D --since-cookie $CK -type f > $OUT/o 2>&1; show $?
touch $D/d0 $D/m1/d2; sync; sleep 2
echo "-- run3 --changelog lfst-MDT0001 --resolve on \$D after d0, m1/d2"; cp $CK $CK.r; $L find $D --changelog lfst-MDT0001 --resolve --since-cookie $CK.r -type f > $OUT/o 2>&1; echo "  rc=$? out=[$(sed "s|$D/||g" $OUT/o | xargs)] cookie.r: $(tr '\n' ';' < $CK.r)"
echo "-- run4 (path)"; $L find $D --since-cookie $CK -type f > $OUT/o 2>&1; show $?
echo "== part 2: a cookie under \$M"
CK=/root/ck.mnt; rm -f $CK
echo "-- m1 (path \$M)"; $L find $M --since-cookie $CK -type f > $OUT/o 2>&1; show $?
touch $D/e0 $D/m1/e1; sync; sleep 2
echo "-- m2 --changelog lfst-MDT0001 on \$M after e0, m1/e1"; $L find $M --changelog lfst-MDT0001 --since-cookie $CK > $OUT/o 2>&1; show $?

echo "-- m3 (path \$M)"; $L find $M --since-cookie $CK -type f > $OUT/o 2>&1; show $?
echo "-- m4 --changelog lfst-MDT0000 (nothing new)"; $L find $M --changelog lfst-MDT0000 --since-cookie $CK > $OUT/o 2>&1; show $?
for m in 0 1; do lctl --device lfst-MDT000$m changelog_deregister cl1; done
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "DNE-CONFIRM DONE"
