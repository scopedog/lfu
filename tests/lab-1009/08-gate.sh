#!/bin/bash
# 10-09 lab, stage 8 (as root): the lookup-time gate (lreview #3 on 68417).
# Usage: 08-gate.sh <arm>...   (llmounts its own one-MDT fs, cleans up)
#
# out.tmp gets two bursts, both before the run: its creation, then 610 s
# later a rename to out.txt behind pad1's creation (so the first burst is
# flushed before the rename joins it).  Both are rejected by -name '*.h5'.
# The second burst predates the first lookup, so the gate skips it:
#   fix (no gate): llapi_scan_fid() calls = candidates + 1
#   gate:          llapi_scan_fid() calls = candidates
# Each arm reads the same log; nothing is written between the arms.
set -u
exec > /tmp/lab1009-gate${GATE_RUN:-}.out 2>&1
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1009-gate-llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000; D=$M/gate
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
U=$(lctl --device $MDT changelog_register -n -m CREAT,RENME,RNMTO)
echo "== start $(date '+%F %T') user $U"
mkdir $D; touch $D/out.tmp; echo "out.tmp $(lfs path2fid $D/out.tmp)"
sleep 610
touch $D/pad1; sync; mv $D/out.tmp $D/out.txt; sync
# past the rename's second: an event in the lookup's own second is looked
# up again, and the first try ran lfs inside it
sleep 2
lfs changelog $MDT | tail -4
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	cat > /tmp/lab1009-gate.gdb <<EOF
set pagination off
set breakpoint pending on
break llapi_scan_fid
commands 1
  silent
  continue
end
run
info breakpoints
EOF
	LD_PRELOAD=$P/lib/liblustreapi.so.1 gdb -q -batch -x /tmp/lab1009-gate.gdb \
		--args $LFS find $D --since 1h -name '*.h5' > /tmp/lab1009-gate-$ARM.txt 2>&1
	echo "$ARM ($(cat /tmp/lab1009-$ARM.sha)): $(grep -o 'already hit [0-9]* time' /tmp/lab1009-gate-$ARM.txt) printed=[$(grep '^/' /tmp/lab1009-gate-$ARM.txt | tr '\n' ' ')]"
done
lctl --device $MDT changelog_deregister $U > /dev/null
bash ./llmountcleanup.sh > /tmp/lab1009-gate-cleanup.txt 2>&1; echo "cleanup rc=$?"
echo GATE DONE
