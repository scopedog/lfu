#!/bin/bash
set -u
H=/home/nishida; L=/tmp/b2g; M=/mnt/lustre
MDT1=$(lctl get_param -n osd-ldiskfs.lustre-MDT0001.mntdev)
echo "=== MDT0001 in service on $MDT1"
for a in F G; do
	# what actually loaded, not what was asked for
	LD_DEBUG=libs LD_DEBUG_OUTPUT=$L/ld.$a \
	LD_PRELOAD=$H/arm$a/lib/liblustreapi.so.1 $H/arm$a/lfs --version \
		>/dev/null 2>&1
	echo "--- arm $a loaded: $(grep -ho '/[^ ]*liblustreapi[^ ]*' $L/ld.$a.* 2>/dev/null | sort -u | head -2 | tr '\n' ' ')"
	LD_PRELOAD=$H/arm$a/lib/liblustreapi.so.1 $H/arm$a/lfs \
		find --device "$MDT1" --fid2path $M -type f \
		> $L/live.$a 2>$L/live.$a.err
	echo "    rc=$? named=$(wc -l < $L/live.$a)  $(cat $L/live.$a.err | head -1)"
	sed 's/^/      /' $L/live.$a
done
echo "=== diff F vs G"; diff $L/live.F $L/live.G && echo "  IDENTICAL"
echo "LIVE2-DONE"
