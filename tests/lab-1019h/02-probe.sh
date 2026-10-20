#!/bin/bash
# 10-20 lab h (root, clone VM): S4 on 68419, the restart probe's third read.
# Usage: 02-probe.sh <arm> <tag>
#
# Held, not raced: lfs runs under gdb with a breakpoint on
# llapi_scan_changelog().  Only stops whose stack holds find_cookie_check()
# count.  At its 2nd read (from the anchor) the other changelog user clears
# the whole log, so that read finds nothing at or after the anchor.  At its
# 3rd read (from 0) lost1..3 and kept1..2 are made and the log is cleared
# through lost3: the oldest record is then past anchor + 1.
set -u
ARM=$1; TAG=$2
L=/tmp/lab1019h-$ARM/lustre/utils/.libs; OUT=/tmp/lab1019h-probe-$TAG
rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') arm=$ARM ($(cat /tmp/lab1019h-$ARM.sha)) tag=$TAG"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; T=/usr/lib64/lustre/tests; cd $T
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; exit 4; }
echo "lfs ld.so: $(LD_TRACE_LOADED_OBJECTS=1 $L/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "arm lib md5 $(md5sum < $L/liblustreapi.so.1.0.0 | cut -c1-12)"

R=$M/r; mkdir $R
U0=$(lctl --device lfst-MDT0000 changelog_register -n)
echo "other changelog user: $U0"
last() { lfs changelog lfst-MDT0000 | tail -1 | awk '{print $1}'; }
cl() { echo "$(lfs changelog lfst-MDT0000 | wc -l) recs, first $(lfs changelog lfst-MDT0000 | head -1 | awk '{print $1}'), last $(last)"; }
CK=$OUT/ck
touch $R/before1 $R/before2; sync
$L/lfs find $R --since-cookie $CK -type f > $OUT/run1.out 2> $OUT/run1.err
echo "run1 rc=$? lines=$(wc -l < $OUT/run1.out) err=[$(cat $OUT/run1.err)]"
echo "cookie after run1: $(grep -v '^#' $CK | tr '\n' ';')  log: $(cl)"

cat > $OUT/w2.sh <<W2
lfs changelog_clear lfst-MDT0000 $U0 0; sync
echo "   [w2] cleared the whole log: \$(lfs changelog lfst-MDT0000 | wc -l) recs"
W2
cat > $OUT/w3.sh <<W3
touch $R/lost1 $R/lost2 $R/lost3; sync
X=\$(lfs changelog lfst-MDT0000 | tail -1 | awk '{print \$1}')
touch $R/kept1 $R/kept2; sync
lfs changelog_clear lfst-MDT0000 $U0 \$X
echo "   [w3] made lost1..3 (to record \$X) and kept1..2, cleared through \$X: first now \$(lfs changelog lfst-MDT0000 | head -1 | awk '{print \$1}')"
W3
cat > $OUT/gdb.py <<PY
import gdb, subprocess
n = [0]
class B(gdb.Breakpoint):
    def stop(self):
        f = gdb.newest_frame(); names = []
        while f is not None and len(names) < 5:
            names.append(f.name()); f = f.older()
        try:
            sr = int(gdb.parse_and_eval('sc->lfsc_startrec'))
        except gdb.error:
            sr = '?'
        hit = 'find_cookie_check' in names
        if hit:
            n[0] += 1
        print('   STOP llapi_scan_changelog startrec=%s %s %s' %
              (sr, '<-'.join(str(x) for x in names[1:]),
               '(check read %d)' % n[0] if hit else ''))
        if hit and n[0] in (2, 3):
            subprocess.run(['bash', '$OUT/w%d.sh' % n[0]])
        return False
B('llapi_scan_changelog')
PY
gdb -batch -ex 'set pagination off' -ex 'set breakpoint pending on' \
    -x $OUT/gdb.py \
    -ex "run find $R --since-cookie $CK -type f > $OUT/run2.out 2> $OUT/run2.err" \
    $L/lfs > $OUT/gdb.txt 2>&1
grep -E 'STOP|\[w[23]\]|exited|Inferior' $OUT/gdb.txt | grep -v 'New Thread\|Thread debugging'
echo "run2 lines=$(wc -l < $OUT/run2.out) lost=$(grep -c /lost $OUT/run2.out) kept=$(grep -c /kept $OUT/run2.out) before=$(grep -c /before $OUT/run2.out)"
sed 's/^/   stderr: /' $OUT/run2.err
echo "cookie after run2: $(grep -v '^#' $CK | tr '\n' ';')  log: $(cl)"
$L/lfs find $R --since-cookie $CK -type f > $OUT/run3.out 2> $OUT/run3.err
echo "run3 rc=$? lines=$(wc -l < $OUT/run3.out) lost=$(grep -c /lost $OUT/run3.out) kept=$(grep -c /kept $OUT/run3.out)"
sed 's/^/   stderr: /' $OUT/run3.err
echo "cookie after run3: $(grep -v '^#' $CK | tr '\n' ';')"
lctl --device lfst-MDT0000 changelog_deregister $U0
cd $T; bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"; echo "PROBE DONE"
