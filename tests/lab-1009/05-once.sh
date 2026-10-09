#!/bin/bash
# 10-09 lab, stage 5 (as root on the clone VM): the 68419 _ONCE loss.
# Usage: 05-once.sh <arm>   (a Lustre fs mounted at $M by llmount.sh)
#
# out.tmp is created, left for longer than sc_min_age (600 s by the stream's
# clock) and followed by PAD later records, so its burst is delivered in the
# middle of the stream.  gdb lets that first lookup return (rejected by
# -name '*.h5') and then renames it to out.h5.  The client reads a plain
# llog's header when it opens it, so the rename is read in the same run only
# if it lands in a later plain llog than the one being read: PAD must span
# more than one plain llog.  The 5000-record first try did not, and both arms
# then printed out.h5 in run 2.
#   old: the rename burst is dropped by _ONCE, the cookie moves past it, and
#        neither run prints out.h5 -- lost.
#   new: the rename burst is looked up again and run 1 prints out.h5.
set -u
ARM=$1; T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
M=${M:-/mnt/lfst}; MDT=${MDT:-lfst-MDT0000}; PAD=${PAD:-150000}
LFS=$T/lustre/utils/.libs/lfs
D=$M/once-$ARM; CK=/tmp/lab1009-$ARM.cookie; OUT=/tmp/lab1009-$ARM-once
rm -rf $OUT; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
export LD_PRELOAD=$P/lib/liblustreapi.so.1
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"

U=$(lctl --device $MDT changelog_register -n -m CREAT,RENME,RNMTO)
echo "changelog user $U"
trap 'lctl --device '"$MDT"' changelog_deregister '"$U"' >/dev/null' EXIT
rm -rf $D $CK; mkdir $D
# anchor the cookie at the end of the log, before out.tmp exists
$LFS find $D --since-cookie $CK -name '*.h5' > $OUT/run0.txt; echo "run0 rc=$?"
cat $CK

touch $D/out.tmp; FID=$($LFS path2fid $D/out.tmp); echo "out.tmp $FID"
echo "waiting 610 s from $(date +%T)"; sleep 610
mkdir $D/pad; /usr/lib64/lustre/tests/createmany -o $D/pad/p $PAD > /dev/null; sync
echo "plain llogs: $(lctl --device $MDT llog_print changelog_catalog 2>/dev/null | grep -c 'catalog entry')"
lctl --device $MDT llog_print changelog_catalog 2>/dev/null | tail -3

cat > $OUT/gdb.cmd <<EOF
set pagination off
set breakpoint pending on
break llapi_scan_fid
run
finish
printf "first lookup returned: renaming\n"
shell mv $D/out.tmp $D/out.h5 && sync
delete
continue
EOF
gdb -q -batch -x $OUT/gdb.cmd --args $LFS find $D --since-cookie $CK \
	-name '*.h5' > $OUT/run1.txt 2> $OUT/run1.err
echo "run1 rc=$?"; grep -v "^\[" $OUT/run1.err | grep -iv "thread\|libthread\|^$" | head
echo "run1 printed: [$(grep -v 'first lookup' $OUT/run1.txt | tr '\n' ' ')]"
grep -q 'first lookup' $OUT/run1.txt $OUT/run1.err || echo "BREAKPOINT NEVER HIT"
echo "run1 lfs output only: [$(grep '^/' $OUT/run1.txt | tr '\n' ' ')]"
echo "cookie after run1:"; cat $CK
echo "the rename record:"
lfs changelog $MDT | grep -E "RENME|RNMTO" | grep -i "out" | tail -2
$LFS find $D --since-cookie $CK -name '*.h5' > $OUT/run2.txt; echo "run2 rc=$?"
echo "run2 printed: [$(tr '\n' ' ' < $OUT/run2.txt)]"
echo "ls: $(ls $D | tr '\n' ' ')"
echo "== end $(date '+%F %T')"
echo ONCE RUN DONE
