#!/bin/bash
# 10-11 lab (as root on the clone VM): the two behaviour changes of the
# round, on arm $1 (tree /tmp/lab1009-$1).
#  G: lfs find SUB --since counts a gone object only if it was under SUB
#  P: LLAPI_SCAN_CL_F_RESOLVE without CAP_DAC_READ_SEARCH is refused
set -u
ARM=$1
T=/tmp/lab1009-$ARM; OUT=/tmp/lab1011-$ARM-extra
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2
M=/mnt/lfst
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }
LFS=$T/lustre/utils/.libs/lfs
CLT=$T/lustre/tests/.libs/llapi_scan_changelog_test
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"
U=$(lctl --device lfst-MDT0000 changelog_register -n)
lctl set_param -n mdd.lfst-MDT0000.changelog_mask=ALL
echo "changelog user $U"
mkdir -p $M/in/sub $M/out
echo x > $M/in/keep
sync; sleep 2

echo "--- G1: nothing deleted"
$LFS find $M/in --since 10m -type f > $OUT/g1.out 2> $OUT/g1.err; echo "rc=$? out=$(wc -l < $OUT/g1.out) err: $(cat $OUT/g1.err)"

echo "--- G2: a file created and deleted OUTSIDE the root"
echo x > $M/out/o1; rm -f $M/out/o1; sync; sleep 2
$LFS find $M/in --since 10m -type f > $OUT/g2.out 2> $OUT/g2.err; echo "rc=$? out=$(wc -l < $OUT/g2.out) err: $(cat $OUT/g2.err)"

echo "--- G3: a file created and deleted INSIDE the root"
echo x > $M/in/sub/i1; rm -f $M/in/sub/i1; sync; sleep 2
$LFS find $M/in --since 10m -type f > $OUT/g3.out 2> $OUT/g3.err; echo "rc=$? out=$(wc -l < $OUT/g3.out) err: $(cat $OUT/g3.err)"

echo "--- G4: the whole filesystem as the root"
$LFS find $M --since 10m -type f > $OUT/g4.out 2> $OUT/g4.err; echo "rc=$? out=$(wc -l < $OUT/g4.out) err: $(cat $OUT/g4.err)"

echo "--- G5: a directory under the root removed with its file (the file's parent is gone too)"
mkdir $M/in/d2; echo x > $M/in/d2/f; rm -rf $M/in/d2; sync; sleep 2
$LFS find $M/in --since 10m -type f > $OUT/g5.out 2> $OUT/g5.err; echo "rc=$? out=$(wc -l < $OUT/g5.out) err: $(cat $OUT/g5.err)"

echo "--- G6: depth options (gone so far under in: sub/i1 d2 d2/f; add top1 at depth 1, sub/deep1 at depth 2)"
echo x > $M/in/top1; rm -f $M/in/top1; echo x > $M/in/sub/deep1; rm -f $M/in/sub/deep1; sync; sleep 2
$LFS find $M/in --since 10m -type f > /dev/null 2> $OUT/g6a.err; echo "no depth:    $(cat $OUT/g6a.err)"
$LFS find $M/in --maxdepth 1 --since 10m -type f > /dev/null 2> $OUT/g6b.err; echo "--maxdepth 1: $(cat $OUT/g6b.err)"
$LFS find $M/in --mindepth 2 --since 10m -type f > /dev/null 2> $OUT/g6c.err; echo "--mindepth 2: $(cat $OUT/g6c.err)"

echo "--- P1: the changelog test as root, all capabilities"
mkdir -p $M/clt
$CLT -m lfst-MDT0000 -u $U -d $M/clt > $OUT/p1.txt 2>&1; echo "rc=$? $(grep -ciE 'pass|ok' $OUT/p1.txt) ok-lines, $(grep -ciE 'fail' $OUT/p1.txt) fail-lines"
tail -3 $OUT/p1.txt | cut -c1-160
echo "--- P2: the same without CAP_DAC_READ_SEARCH"
which capsh > /dev/null || echo "no capsh"
capsh --drop=cap_dac_read_search -- -c "$CLT -m lfst-MDT0000 -u $U -d $M/clt" > $OUT/p2.txt 2>&1; echo "rc=$?"
grep -iE "EPERM|Operation not permitted|by FID|fail|unresolved" $OUT/p2.txt | head -6 | cut -c1-200
tail -2 $OUT/p2.txt | cut -c1-160

lctl --device lfst-MDT0000 changelog_deregister $U > /dev/null
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "EXTRA RUN DONE"
