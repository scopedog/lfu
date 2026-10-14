#!/bin/bash
# 10-13 lab (as root on the clone VM): lreview run4 on 68163, destroyed pools.
# Usage: 12-zfs-destroyed.sh <arm>
#  D1: a destroyed pool's labels are still under the search path.
#      zpool import does not list it (only -D does).  Does the scan read it?
#  D2: a pool of the same name created again on another vdev beside it.
#      zpool import lists one.  Does the scan answer -EINVAL?
set -u
ARM=$1; T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
O=/tmp/lab1013-zd; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=/tmp/zfslab1013d LUSTRE=/usr/lib64/lustre
rm -rf $TMP; mkdir -p $TMP
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/zfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
mkdir $M/z; ./createmany -o $M/z/f 500 > /dev/null; sync; sleep 3
DS=$(zfs list -H -o name | grep -m1 'mdt1/'); POOL=${DS%%/*}
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1
zpool list -H -o name 2>/dev/null | grep -qx $POOL && zpool export $POOL
scan() {
	LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device $DS --search $TMP > $O/$1.out 2> $O/$1.err
	echo "  scan: rc=$? lines=$(wc -l < $O/$1.out) err: $(head -2 $O/$1.err | tr '\n' '|')"
}
echo "--- D0: exported pool $POOL ($DS), vdevs: $(ls $TMP | tr '\n' ' ')"
scan d0
echo "--- D1: zpool destroy $POOL"
zpool import -d $TMP $POOL && zpool destroy $POOL || echo "  destroy failed"
echo "  zpool import -d: $(zpool import -d $TMP 2>&1 | grep -c 'pool:') pools; with -D: $(zpool import -D -d $TMP 2>&1 | grep 'pool:\|state:' | tr -s ' ' | tr '\n' ' ')"
scan d1
echo "--- D2: a new $POOL on another vdev in $TMP"
truncate -s 512M $TMP/new-vdev
zpool create -o cachefile=none $POOL $TMP/new-vdev && zfs create $DS && touch /$DS/x 2>/dev/null; zpool export $POOL
echo "  zpool import -d: $(zpool import -d $TMP 2>&1 | grep 'pool:\|state:' | tr -s ' ' | tr '\n' ' ')"
scan d2
zpool import -d $TMP $POOL 2>/dev/null && zpool destroy $POOL
zpool list 2>&1 | head -2
rm -rf $TMP
echo "== end $(date '+%F %T')"
echo ZD DONE
