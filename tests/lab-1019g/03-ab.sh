#!/bin/bash
# 10-20 lab g (root, clone VM): R6 A/B on one node serving MDT + 2 OSTs.
# Fixture built ONCE, then each arm's lfs (RPATH -> its own prefix: lib and
# plugin) runs the same searches against the mounted targets.
set -u
OUT=/tmp/lab1019g-ab; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfsg MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfsg
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client"; exit 4; }
echo "loaded version: [$(lctl get_param -n version | head -1)]"
lctl get_param -n 'osd-*.*.mntdev' 2>/dev/null | sed 's/^/mntdev: /'

lctl pool_new lfsg.flash && lctl pool_add lfsg.flash lfsg-OST0000
sleep 5
mkdir $M/p $M/w
lfs setstripe -p flash -c 1 $M/p
lfs setstripe -c 2 $M/w
C=/usr/lib64/lustre/tests/createmany
$C -o $M/p/f 10 >/dev/null; $C -o $M/w/f 5 >/dev/null
for f in $M/p/f* $M/w/f*; do echo x > $f; done
sync; sync; sleep 2; sync
echo "client: pool=$(lfs find $M --pool flash -type f | wc -l)" \
     "c1=$(lfs find $M --stripe-count 1 -type f | wc -l)" \
     "all=$(lfs find $M -type f | wc -l)"

run() {		# arm tag args...
	local n=$1 tag=$2; shift 2
	local L=/tmp/lab1019g-$n/lustre/utils/.libs/lfs
	$L find "$@" > $OUT/$n-$tag.out 2> $OUT/$n-$tag.err
	local rc=$?
	echo "  [$n] $tag: rc=$rc out=$(wc -l < $OUT/$n-$tag.out)" \
	     "ost-errs=$(grep -c 'need an MDT' $OUT/$n-$tag.err)" \
	     "err-lines=$(wc -l < $OUT/$n-$tag.err)"
	sed 's/^/      err: /' $OUT/$n-$tag.err | head -6
}
for n in o t; do
	L=/tmp/lab1019g-$n/lustre/utils/.libs/lfs
	echo "--- arm $n ($(cat /tmp/lab1019g-$n.sha)): $(LD_TRACE_LOADED_OBJECTS=1 $L | grep lustreapi | tr -s ' \t' ' ')"
	run $n pool --local --pool flash --type f
	run $n c1 --local --stripe-count 1 --type f
	run $n fspool --fsname lfsg --pool flash --type f
	run $n tgtpool --target lfsg-OST0000 --pool flash
	run $n ostpool --local --ost lfsg-OST0000 --pool flash
	run $n mdtpool --local --mdt lfsg-MDT0000 --pool flash --type f
	run $n plain --local --type f
done
for t in pool c1 fspool plain; do
	cmp -s <(sort $OUT/o-$t.out) <(sort $OUT/t-$t.out) &&
		echo "same stdout o/t: $t" || echo "DIFF stdout o/t: $t"
done

# the no-MDT sweep: only the OSTs of the node (MDT stopped)
umount $M
for d in $(mount -t lustre | awk '$1 ~ /mds/ {print $3}'); do umount $d; done
mount -t lustre | awk '{print "still mounted: "$3}'
for n in o t; do
	run $n nomdt-pool --local --pool flash --type f
done

bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
mount -t lustre | awk '{print "left mounted: "$3}'
echo "== end $(date '+%F %T')"
echo "AB DONE"
