#!/bin/bash
# 10-19 lab d (root): L1 A/B, what each library delivers.  User cl1 is
# registered with -m creat, the scan asks for CL_UNLINK only.
#  1) mdd mask MARK + cl1's CREAT: no UNLNK record exists.  o: every type;
#     t: none.
#  2) changelog_mask=+UNLNK, new events: o: every type; t: UNLNK only.
#  3) control: a user -m all, same ask: both UNLNK only (the mdc filters).
set -u
OUT=/tmp/lab1019d-l1b; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
T=/tmp/lab1019d-t
gcc -O2 -Wall -o $OUT/cltypes /tmp/cltypes.c -I $T/lustre/include -I $T/include -I $T/include/uapi \
	-L $T/lustre/utils/.libs -llustreapi || exit 1
cd /usr/lib64/lustre/tests
export FSNAME=lfsl MDSCOUNT=1 OSTCOUNT=1 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfsl; MDT=lfsl-MDT0000; D=$M/d
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client"; exit 4; }
ev() { mkdir -p $D; for i in 1 2 3; do touch $D/f$i; chmod 600 $D/f$i; rm $D/f$i; done; sync; }
run() {
	for n in o t; do
		L=/tmp/lab1019d-$n/lustre/utils/.libs/liblustreapi.so.1
		echo "  lib $n ($(cat /tmp/lab1019d-$n.sha)): $(LD_PRELOAD=$L $OUT/cltypes $MDT $1 $2)"
	done
}
U=$(lctl --device $MDT changelog register -n -m creat)
echo "loads: $(LD_PRELOAD=$T/lustre/utils/.libs/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 $OUT/cltypes | grep lustreapi | tr -s ' \t' ' ')"
UNLNK=$(printf '%x' $((1 << 6)))
ev
echo "1) $U $(lctl get_param -n mdd.$MDT.changelog_users | grep "^$U" | awk '{print $NF}'), mdd mask: $(lctl get_param -n mdd.$MDT.changelog_mask)"
run $U $UNLNK
lctl set_param -n mdd.$MDT.changelog_mask=+UNLNK
ev
echo "2) mdd mask: $(lctl get_param -n mdd.$MDT.changelog_mask)"
run $U $UNLNK
V=$(lctl --device $MDT changelog register -n -m all)
echo "3) control user $V -m all"
run $V $UNLNK
echo "   and all types for $V:"
run $V 0
lctl --device $MDT changelog deregister $U
lctl --device $MDT changelog deregister $V
echo "== end $(date '+%F %T')"
bash ./llmountcleanup.sh > $OUT/clean.txt 2>&1
echo "L1B DONE"
