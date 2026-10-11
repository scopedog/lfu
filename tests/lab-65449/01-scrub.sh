#!/bin/bash
# 65449 review, stage 1 (as root on the clone VM): sanity-scrub from the
# build tree.  Usage: r65449-scrub.sh <arm>   (A = OSD tip, B = + 65449)
set -u
ARM=$1; T=/tmp/osd1007-tip; OUT=/tmp/r65449-$ARM-scrub${TAG:-}
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
lsmod | grep -q '^lustre\|^obdclass' && { echo "ABORT: modules loaded"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
grep -c "os_partial_scan" $T/lustre/include/lustre_scrub.h
dmesg -C
cd $T/lustre/tests
export FSNAME=lfst MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=2 PDSH="pdsh -S -Rssh -w"
bash ./sanity-scrub.sh > $OUT/sanity-scrub.txt 2>&1
echo "RC=$?"
grep -E "^(PASS|FAIL|SKIP) |: FAIL:|SKIP:" $OUT/sanity-scrub.txt | cut -c1-170 > $OUT/verdicts.txt
echo "PASS $(grep -c '^PASS' $OUT/verdicts.txt)  FAIL $(grep -c '^FAIL' $OUT/verdicts.txt)  SKIP $(grep -c '^SKIP' $OUT/verdicts.txt)"
grep -E "FAIL|SKIP" $OUT/verdicts.txt
dmesg | grep -E "LBUG|ASSERTION|BUG:|Oops|Call Trace" | head -5
mount | grep ' type lustre' && bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1
lsmod | grep -c lustre
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "SCRUB RUN DONE"
