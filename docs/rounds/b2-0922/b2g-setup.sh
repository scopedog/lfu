#!/bin/bash
# Batch 2 second pass: does --fid2path name a DNE remote subtree when the
# MDT holding it is in service, and does nothing move when it is not?
# Arms: F = b2-tip (no fall back at all), G = b2b-tip (fall back, gated).
set -u
H=/home/nishida; L=/tmp/b2g; T=${T:-$H/lustre-0918}; M=/mnt/lustre
export HOME=/root PDSH="ssh -o StrictHostKeyChecking=no -x"
mkdir -p $L
cd $T/lustre/tests || exit 1

./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo "NOMOUNT"; tail -15 $L/mount.log; exit 1; }

D=$M/b2g
rm -rf $D; mkdir -p $D
lfs mkdir -i 1 $D/remote || { echo "no remote dir"; exit 1; }
touch $D/remote/rf1 $D/remote/rf2
mkdir -p $D/remote/sub && touch $D/remote/sub/rf3
touch $D/local1
sync

echo "=== where the fixture landed"
for p in $D $D/remote $D/remote/rf1 $D/remote/sub/rf3 $D/local1; do
	echo "  $p  $(lfs getstripe -m $p 2>/dev/null)  $(lfs path2fid $p)"
done
echo "=== mntdev"
lctl get_param -n osd-ldiskfs.lustre-MDT0000.mntdev osd-ldiskfs.lustre-MDT0001.mntdev
echo "=== backing files"
ls -l /tmp/lustre-mdt* /tmp/lustre-ost* 2>/dev/null
echo "=== lfu"
modprobe lfu 2>&1 | head -2
ls -l /dev/lfu 2>/dev/null || echo "  NO /dev/lfu"
echo "SETUP-DONE"
