#!/bin/bash
# 10-13 lab (as root on the clone VM): the 68418 lreview finding.  Does
# `lfs find --changelog --resolve -printf` end when OPEN is in the changelog
# mask?  Each lookup opens the file, and each open appends CL_OPEN/CL_CLOSE
# behind the reader.  Usage: 03-selffeed.sh <arm> [seconds for arm C]
#  A: default mask, 120000 files          -> must end (control)
#  B: mask +OPEN,   5000 files            -> ends (all objects fit the cache)
#  C: mask +OPEN,   120000 files (> sc_max_cached 100000)
#     the finding says: never ends, the same files print again, the log grows
set -u
ARM=$1; CSEC=${2:-300}
T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
O=/tmp/lab1013-sf; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
# the default MDT image holds about 100000 inodes: too few for A + B + C
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre MDSSIZE=2000000
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
export LD_PRELOAD=$P/lib/liblustreapi.so.1
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"
unset LD_PRELOAD
U=$(lctl --device $MDT changelog_register -n)
DEFMASK=$(lctl get_param -n mdd.$MDT.changelog_mask)
cur() { lctl get_param -n mdd.$MDT.changelog_users | awk '/current.index/ { print $NF }'; }
run() {	# name seconds
	local name=$1 sec=$2 rc
	local before=$(cur) t0=$(date +%s)
	LD_PRELOAD=$P/lib/liblustreapi.so.1 timeout $sec $LFS find $M \
		--changelog $MDT --resolve -printf "%p\n" \
		> $O/$name.out 2> $O/$name.err &
	local pid=$!
	while kill -0 $pid 2>/dev/null; do
		sleep 20
		echo "  $name t+$(( $(date +%s) - t0 ))s: lines=$(wc -l < $O/$name.out) log index=$(cur)"
	done
	wait $pid; rc=$?
	echo "$name: rc=$rc (124 = still running at ${sec}s) in $(( $(date +%s) - t0 ))s; lines=$(wc -l < $O/$name.out) distinct=$(sort -u $O/$name.out | wc -l) most-repeated=$(sort $O/$name.out | uniq -c | sort -rn | head -1 | awk '{print $1}'); log index $before -> $(cur); err: $(head -2 $O/$name.err | tr '\n' '|')"
}
fresh() {	# dir count
	lfs changelog_clear $MDT $U 0
	mkdir $M/$1 && ./createmany -m $M/$1/f $2 > /dev/null ||
		{ echo "ABORT: cannot create $2 files in $1"; exit 5; }
	sync; sleep 2
	[ $(ls -f $M/$1 | wc -l) -ge $2 ] || { echo "ABORT: $1 is short"; exit 5; }
	echo "--- $1: $2 files, mask [$(lctl get_param -n mdd.$MDT.changelog_mask)], log holds $(lfs changelog $MDT | wc -l) records"
}
fresh a 120000; run A 600
lctl set_param -n mdd.$MDT.changelog_mask="+OPEN"
fresh b 5000;   run B 600
fresh c 120000; run C $CSEC
lctl set_param -n mdd.$MDT.changelog_mask="$DEFMASK"
lctl --device $MDT changelog_deregister $U > /dev/null
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo SELFFEED DONE
