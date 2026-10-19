#!/bin/bash
# 10-19 lab c (root): the MDT half of 04-hand.sh, whose mount-point match
# missed the MDT; the image it left behind, read with arm t.
set -u
L=/tmp/lab1019c-t/lustre/utils/.libs/lfs; OUT=/tmp/lab1019c-hand
exec > $OUT/mdt-run.txt 2>&1
echo "== start $(date '+%F %T')"
mount -t lustre | awk '{print "mounted: "$3}'
$L find --device /tmp/lfsh-mdt1 --type f -printf '%LF %LO\n' | sort | tee $OUT/mdt.txt
echo "--- --type d -printf '%LF [%LO]' (a directory has no OST objects)"
$L find --device /tmp/lfsh-mdt1 --type d -printf '%LF [%LO]\n' | head -4
ok=0; bad=0
while read -r p fid lo; do
	[[ -z "$lo" ]] && continue      # the directories
	grep -qxF "$fid $lo" $OUT/mdt.txt && ok=$((ok+1)) ||
		{ bad=$((bad+1)); echo "MDT MISS $p $fid $lo"; }
done < $OUT/walk.txt
echo "MDT: $ok files match the walk, $bad do not"
echo "== end"
