#!/bin/bash
# Batch 1: the round-20/21 device-scan changes on the ZFS backend.
# 68163 is the ZFS backend, so its batch is the one that has to show these
# two behave the same way there as on ldiskfs:
#   68156  a striped directory's size and blocks are withheld
#   68156  an OST data object keeps its own blocks (the lreview defect)
# B = r0921-tip (OST defect present), C = r0921b-tip (fixed).  The ZFS
# backend itself is identical in both -- it is a dlopen'd plugin and
# libscan_zfs.c did not change -- so the arms differ only in liblustreapi,
# which is where scan_size() lives.
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
echo "=== tearing down whatever is up"
./llmountcleanup.sh > $L/zfs-cleanup0.log 2>&1 || true

echo "=== formatting and mounting a ZFS filesystem (2 MDTs, 1 OST)"
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/zfs-llmount.log 2>&1 || true
if ! mount -t lustre | grep -q "on $M "; then
	echo "llmount(zfs) did not mount $M"; tail -25 $L/zfs-llmount.log; exit 1
fi
echo "=== loaded: $(lctl get_param -n version)"
zpool list

D=$M/r21zfs
rm -rf $D; mkdir -p $D
$H/armC/lfs setdirstripe -c 2 $D/zstriped || exit 1
touch $D/zstriped/a $D/zstriped/b
$H/armC/lfs setstripe -c 1 -i 0 $D/zbig || exit 1
dd if=/dev/zero of=$D/zbig bs=1M count=4 conv=fsync status=none || exit 1
sync
echo "=== the client's view:"
stat -c '  %n size=%s blocks=%b' $D/zbig $D/zstriped

# what a walk reports for the striped directory, the oracle for arm 1
for arm in B C; do
	run $arm $H/scanrec $D 2>/dev/null > $L/zwalk.$arm
done
echo "--- what a walk reports on ZFS (arm C):"
sed 's/^/    /' $L/zwalk.C

echo "=== stopping the filesystem and exporting the pools"
./llmountcleanup.sh > $L/zfs-cleanup.log 2>&1
mount -t lustre | grep -q "on $M " && { echo "still mounted"; exit 1; }
# the scan refuses an imported pool, so export every one that survived
for p in $(zpool list -H -o name 2>/dev/null); do
	zpool export $p 2>&1 | sed "s|^|  export $p: |"
done
echo "  pools still imported: [$(zpool list -H -o name 2>/dev/null | tr '\n' ' ')]"

# the pools live on file vdevs under $TMP, so the scan is told where to look
MDTDS=$(zpool list -H -o name 2>/dev/null | head -1)
SDIR=/tmp
MDT=lustre-mdt1/mdt1
OST=lustre-ost1/ost1
echo "=== datasets: MDT=$MDT OST=$OST search=$SDIR"

########## the striped directory, from a ZFS MDT
for arm in B C; do
	run $arm $H/arm$arm/lfs find --device $MDT --search $SDIR -name zstriped \
	    -printf '%s %b\n' > $L/zdev.$arm 2>&1
	echo "  arm $arm striped dir: $(tr '\n' '|' < $L/zdev.$arm)"
done
if grep -qE "^(0 0|4096 0)$" $L/zdev.C 2>/dev/null ||
   [ "$(head -1 $L/zdev.C)" = "0 0" ]; then
	ok "a ZFS MDT withholds the striped directory's size and blocks"
else
	bad "the ZFS MDT answered a size for the striped directory" "$(cat $L/zdev.C)"
fi

########## the OST data object, the lreview defect
for arm in B C; do
	run $arm $H/arm$arm/lfs find --device $OST --search $SDIR -type f \
	    -printf '%s %b\n' 2>/dev/null | sort -rn | head -3 > $L/zost.$arm
	echo "  arm $arm OST top 3: $(tr '\n' '|' < $L/zost.$arm)"
done
if diff -q $L/zost.B $L/zost.C >/dev/null; then
	bad "the ZFS OST scan answers the same in both arms" "$(cat $L/zost.C)"
else
	ok "the ZFS OST scan changed: B=$(head -1 $L/zost.B) C=$(head -1 $L/zost.C)"
fi
if awk '{ if ($2 != 0) f=1 } END { exit !f }' $L/zost.C; then
	ok "arm C reports non-zero blocks for a ZFS OST data object"
else
	bad "arm C still reports 0 blocks on ZFS" "$(cat $L/zost.C)"
fi
echo "=== $pass passed, $fail failed"
exit $((fail > 0))
