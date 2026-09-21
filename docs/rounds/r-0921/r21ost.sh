#!/bin/bash
# Round 21, the lreview finding: an OST data object's blocks.
# B = r0921-tip (the defect, inherited from round 20), C = r0921b-tip (fixed).
# The fixture needs a file with actual data -- the earlier one was all empty
# files, where 0 blocks and the real count are the same number.
set -u
T=${T:-/home/nishida/lustre-0918}
M=${M:-/mnt/lustre}
H=/home/nishida
L=/tmp/r21lab
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
run() { local arm=$1; shift; LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"; }

cd $T/lustre/tests || exit 1
if ! mount -t lustre | grep -q "on $M "; then
	echo "=== mounting"
	MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/llmount2.log 2>&1 || true
	mount -t lustre | grep -q "on $M " || { echo "no mount"; tail -5 $L/llmount2.log; exit 1; }
fi
D=$M/r21ost
rm -rf $D; mkdir -p $D
# one file with real data, one empty, both single-striped on OST0
$H/armC/lfs setstripe -c 1 -i 0 $D/big || exit 1
dd if=/dev/zero of=$D/big bs=1M count=4 conv=fsync status=none || exit 1
touch $D/empty
sync
echo "=== client's view:"
stat -c '  %n size=%s blocks=%b' $D/big $D/empty
sync; sleep 2

echo "=== stopping the filesystem"
./llmountcleanup.sh > $L/cleanup2.log 2>&1
mount -t lustre | grep -q "on $M " && { echo "still mounted"; exit 1; }

OST=/tmp/lustre-ost1
ls -la $OST || exit 1
# every OST data object, with its size and blocks
for arm in B C; do
	run $arm $H/arm$arm/lfs find --device $OST -type f -printf '%s %b\n' \
	    2>/dev/null | sort -rn | head -5 > $L/ost.$arm
	echo "  arm $arm (top 5 by size): $(tr '\n' '|' < $L/ost.$arm)"
done
if diff -q $L/ost.B $L/ost.C >/dev/null; then
	bad "the OST scan answers the same in both arms" "$(cat $L/ost.C)"
else
	ok "the OST scan changed: B=$(head -1 $L/ost.B) C=$(head -1 $L/ost.C)"
fi
if awk '{ if ($2 != 0) found=1 } END { exit !found }' $L/ost.C; then
	ok "arm C reports non-zero blocks for OST data objects"
else
	bad "arm C still reports 0 blocks everywhere" "$(cat $L/ost.C)"
fi
if awk '{ if ($2 != 0) found=1 } END { exit found }' $L/ost.B; then
	ok "arm B reported 0 blocks for every OST object, which is the defect"
else
	bad "arm B did not show the defect" "$(cat $L/ost.B)"
fi
# the MDT side must not move: a regular file on an MDT still has 0 blocks
for arm in B C; do
	run $arm $H/arm$arm/lfs find --device /tmp/lustre-mdt1 -name big \
	    -printf '%s %b\n' 2>/dev/null > $L/mdtbig.$arm
done
if diff -q $L/mdtbig.B $L/mdtbig.C >/dev/null; then
	ok "the MDT answer for the same file is unchanged ($(head -1 $L/mdtbig.C))"
else
	bad "the MDT answer moved" "$(diff $L/mdtbig.B $L/mdtbig.C | head -4)"
fi
echo "=== $pass passed, $fail failed"
exit $((fail > 0))
