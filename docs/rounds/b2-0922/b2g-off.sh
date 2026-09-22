#!/bin/bash
# The gate: MDT0001 stopped, the rest of the filesystem up, so --fid2path
# has a mount and the lookup would go to the stopped target.  G must not
# take it -- and must not wait for it either.
set -u
H=/home/nishida; L=/tmp/b2g; M=/mnt/lustre
run() { local a=$1; shift
	timeout 120 env LD_PRELOAD=$H/arm$a/lib/liblustreapi.so.1 $H/arm$a/lfs "$@"; }

echo "=== stopping MDT0001 only"
umount /mnt/lustre-mds2 2>&1 | head -2
sleep 2
mount -t lustre | sed 's/^/  /'
echo "=== the client mount is still there: $(ls $M | tr '\n' ' ')"

for a in F G; do
	s=$(date +%s)
	run $a find --device /tmp/lustre-mdt2 --fid2path $M -type f \
		> $L/off.$a 2>$L/off.$a.err
	rc=$?
	echo "--- arm $a rc=$rc in $(( $(date +%s) - s ))s named=$(wc -l < $L/off.$a)"
	head -2 $L/off.$a.err | sed 's/^/      /'
	sed 's/^/      /' $L/off.$a
done
echo "=== diff F vs G (--fid2path on a stopped MDT)"
diff $L/off.F $L/off.G && echo "  IDENTICAL"

for a in F G; do
	run $a find --device /tmp/lustre-mdt2 --paths -type f 2>/dev/null |
		sort > $L/offp.$a
done
echo "=== --paths on the stopped MDT: $(wc -l < $L/offp.G) line(s)"
diff $L/offp.F $L/offp.G && echo "  IDENTICAL" || true
sed 's/^/      /' $L/offp.G

for a in F G; do
	run $a find --device /tmp/lustre-mdt2 -type f 2>&1 | sort > $L/offplain.$a
done
echo "=== a plain scan, no naming option"
diff $L/offplain.F $L/offplain.G > /dev/null && echo "  IDENTICAL ($(wc -l < $L/offplain.G) lines)" || echo "  MOVED"

echo "OFF-DONE"
