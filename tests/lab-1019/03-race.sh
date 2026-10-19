#!/bin/bash
# 10-19 lab (root, clone VM): #8 A/B and #6 A/B on one mount.
# #8: llapi_scan_fid() on file f (object A, 100 bytes, projid 1001) while
# an open() shim renames f.new (object B, 200 bytes, projid 2002) over f at
# the gather's first open by name.  Cases: plain (no race), race (A
# unlinked by the rename), backup (A moved to f.bak first).  Each run gets
# its own fresh directory; the arms alternate, twice.
# #6: the n arm's llapi_scan_changelog_test -o 4, with each arm's library.
set -u
OUT=/tmp/lab1019-race; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') o=$(cat /tmp/lab1019-o.sha) n=$(cat /tmp/lab1019-n.sha)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst
cd /usr/lib64/lustre/tests
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
lfs mkdir -i 0 $M/race || exit 5
fixture() {	# $1 = dir
	mkdir $1 || exit 6
	head -c 100 /dev/zero > $1/f; head -c 200 /dev/zero > $1/f.new
	lfs project -p 1001 $1/f; lfs project -p 2002 $1/f.new
	echo "  A=$(lfs path2fid $1/f) projid $(lfs project $1/f | awk '{print $1}')  B=$(lfs path2fid $1/f.new) projid $(lfs project $1/f.new | awk '{print $1}')"
}
for round in 1 2; do
for c in plain race backup; do
for arm in o n; do
	d=$M/race/$c-$arm-$round
	echo "### $c arm=$arm round $round"
	fixture $d
	case $c in
	plain)	env LD_PRELOAD=/tmp/race_open.so /tmp/scanfid_race-$arm $M $d/f ;;
	race)	env LD_PRELOAD=/tmp/race_open.so RACE_PATH=$d/f RACE_FROM=$d/f.new \
			/tmp/scanfid_race-$arm $M $d/f ;;
	backup)	env LD_PRELOAD=/tmp/race_open.so RACE_PATH=$d/f RACE_FROM=$d/f.new \
			RACE_BACKUP=$d/f.bak /tmp/scanfid_race-$arm $M $d/f ;;
	esac
	echo "  after: $(cd $d && for x in *; do echo -n "$x=$(lfs path2fid $x) "; done)"
done; done; done

echo "### #6: llapi_scan_changelog_test -o 4 (n binary) with each library"
CB=/tmp/lab1019-n/lustre/tests/.libs/llapi_scan_changelog_test
[ -f $CB ] || CB=/tmp/lab1019-n/lustre/tests/llapi_scan_changelog_test
MDT=lfst-MDT0000
U=$(lctl --device $MDT changelog_register -m ALL 2>&1 | grep -o "cl[0-9][0-9]*" | head -1)
echo "  mdt=$MDT user=$U"
lfs mkdir -i 0 $M/llapi_scan_changelog_test.d
for arm in o n o n; do
	echo "## lib=$arm"
	env LD_PRELOAD=/tmp/arm1019$arm/lib/liblustreapi.so.1 $CB -m $MDT -d $M -u $U -o 4 2>&1 | tail -4
	echo "  rc=${PIPESTATUS[0]}"
done
lctl --device $MDT changelog_deregister $U
bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
