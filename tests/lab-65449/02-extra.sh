#!/bin/bash
# 65449 review, stage 2 (as root on the clone VM): the two extra observations,
# appended to the arm's own sanity-scrub.sh.  Usage: r65449-extra.sh <arm>
set -u
ARM=$1; T=/tmp/osd1007-tip; OUT=/tmp/r65449-$ARM-extra${TAG:-}
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd $T/lustre/tests
python3 - <<PY
s=open('sanity-scrub.sh').read()
x=open('/tmp/r65449-extra-tests.sh').read()
m='OSTCOUNT=\${SAVED_OSTCOUNT}\n\n# cleanup the system at last'
assert s.count(m)==1
open('r65449-scrub-extra.sh','w').write(s.replace(m, x+'\n'+m))
PY
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 PDSH="pdsh -S -Rssh -w"
dmesg -C
ONLY="${ONLY:-90a 90b}" REFORMAT=yes bash ./r65449-scrub-extra.sh > $OUT/extra.txt 2>&1
echo "RC=$?"
grep -E "^(R2|S1) |^(PASS|FAIL|SKIP) |: FAIL:" $OUT/extra.txt | cut -c1-260
mount | grep -E 'scan_osd_kernel|r65449-brpt' && echo "MOUNT LEFT"
mount | grep ' type lustre' && bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1
lsmod | grep -c lustre
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "EXTRA RUN DONE"
