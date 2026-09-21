#!/bin/bash
# The %Lh defect lreview found on 68159: with only -printf '%Lh', a device
# scan never asked for the directory stripe, so every directory printed hash
# type "none" -- mdt_hash_name[0] -- instead of its own.  A walk was right,
# because -printf sets gather_all there.
# C = r0921b-tip (the defect), D = b1-tip (fixed).
set -u
T=${T:-/home/nishida/lustre-0918}
M=${M:-/mnt/lustre}
H=/home/nishida; L=/tmp/r21lab
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
run() { local arm=$1; shift; LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"; }

cd $T/lustre/tests || exit 1
# always format: the previous run may have left a ZFS filesystem mounted,
# and then /tmp/lustre-mdt1 is a pool vdev rather than an ldiskfs target
./llmountcleanup.sh > $L/lh-clean0.log 2>&1 || true
for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p 2>/dev/null; done
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/lh-mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -15 $L/lh-mount.log; exit 1; }
echo "=== fstype: $(mount | grep -m1 'lustre-mdt1\|/mnt/mds1' | head -1)"
D=$M/r21lh; rm -rf $D; mkdir -p $D
# a striped directory with a hash type that is not the default
$H/armD/lfs setdirstripe -c 2 -i 0 -H fnv_1a_64 $D/hashed || exit 1
touch $D/hashed/f
sync
echo "=== what the client says its hash type is:"
$H/armD/lfs getdirstripe -H $D/hashed 2>&1 | sed 's/^/    /'
echo "=== the walk, which was always right (arm C):"
run C $H/armC/lfs find $D -name hashed -printf '%p %Lh\n' 2>&1 | sed 's/^/    /'

echo "=== stopping"
./llmountcleanup.sh > $L/lh-clean.log 2>&1
for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p 2>/dev/null; done

MDT=/tmp/lustre-mdt1
for arm in C D; do
	run $arm $H/arm$arm/lfs find --device $MDT -name hashed -printf '%Lh\n' \
	    > $L/lh.$arm 2>&1
	echo "  arm $arm device scan: [$(tr '\n' '|' < $L/lh.$arm)]"
done
if grep -q "none" $L/lh.C; then
	ok "arm C shows the defect: the device scan prints hash type none"
else
	bad "arm C did not show the defect" "$(cat $L/lh.C)"
fi
if grep -q "fnv_1a_64" $L/lh.D; then
	ok "arm D prints the directory's real hash type"
else
	bad "arm D did not print the real hash type" "$(cat $L/lh.D)"
fi
# and a format that already worked must not change
for arm in C D; do
	run $arm $H/arm$arm/lfs find --device $MDT -name hashed -printf '%Lc\n' \
	    > $L/lhc.$arm 2>&1
done
if diff -q $L/lhc.C $L/lhc.D >/dev/null; then
	ok "%Lc is unchanged between the arms ([$(tr '\n' '|' < $L/lhc.D)])"
else
	bad "%Lc moved" "$(diff $L/lhc.C $L/lhc.D | head -4)"
fi
echo "=== $pass passed, $fail failed"
