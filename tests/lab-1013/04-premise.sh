#!/bin/bash
# 10-13 lab (as root on the clone VM): the premise under the 68418 finding.
# Does a plain (non-FOLLOW) changelog reader see records appended after it
# started?  A reader is stalled early in a 20000-record log (its consumer
# sleeps, the pipe fills), records are appended, and the reader goes on.
#  P1: 5000 appended    P2: 150000 appended (more than one plain llog holds)
set -u
O=/tmp/lab1013-pr; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre MDSSIZE=2000000
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
U=$(lctl --device $MDT changelog_register -n)
cur() { lctl get_param -n mdd.$MDT.changelog_users | awk '/current.index/ { print $NF }'; }
arm() {	# name appended stall-seconds
	local name=$1 add=$2 stall=$3
	lfs changelog_clear $MDT $U 0
	mkdir $M/$name-a $M/$name-b
	./createmany -m $M/$name-a/f 20000 > /dev/null; sync; sleep 2
	local first=$(lfs changelog $MDT | head -1 | awk '{print $1}') end0=$(cur)
	lfs changelog $MDT | awk -v s=$stall 'NR == 100 { system("sleep " s) } { last = $1 } END { print NR, last }' > $O/$name.txt &
	local pid=$!
	sleep 3
	./createmany -m $M/$name-b/f $add > /dev/null; sync
	local end1=$(cur)
	wait $pid
	read n last < $O/$name.txt
	echo "$name: log $first..$end0 when the reader started, ..$end1 after $add more creates; the reader returned $n records, the last one $last ($(( last - end0 )) past its starting end)"
}
arm P1 5000 25
arm P2 150000 150
lctl --device $MDT changelog_deregister $U > /dev/null
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo PREMISE DONE
