#!/bin/bash
# G (gated) against H (the same build with the gate forced open), both on a
# STOPPED MDT0001 with the client mount still up.
set -u
H=/home/nishida; L=/tmp/b2g; M=/mnt/lustre
mount -t lustre | grep -q lustre-mds2 && { echo "MDT0001 is still mounted"; exit 1; }
for a in G H; do
	s=$(date +%s)
	timeout 180 env LD_PRELOAD=$H/arm$a/lib/liblustreapi.so.1 $H/arm$a/lfs \
		find --device /tmp/lustre-mdt2 --fid2path $M -type f \
		> $L/ctl.$a 2>$L/ctl.$a.err
	rc=$?
	echo "--- arm $a rc=$rc in $(( $(date +%s) - s ))s named=$(wc -l < $L/ctl.$a)"
	head -2 $L/ctl.$a.err | sed 's/^/      /'
done
echo "CTL-DONE"
