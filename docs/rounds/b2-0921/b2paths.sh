#!/bin/bash
# Batch 2: the dirmap gate moves from "the map found something" to "the
# pre-pass ran".  The difference only shows on an MDT whose map comes back
# empty, which needs a DNE shape this rig cannot build cheaply -- so what is
# measured here is that the ordinary cases do not move.
# D = b1-tip (dm_used gate), F = b2-tip (pp_ran gate).
set -u
T=${T:-/home/nishida/lustre-0918}; M=${M:-/mnt/lustre}
H=/home/nishida; L=/tmp/r21lab
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
run() { local arm=$1; shift; LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"; }

cd $T/lustre/tests || exit 1
./llmountcleanup.sh > $L/b2-clean0.log 2>&1 || true
for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p 2>/dev/null; done
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/b2-mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -12 $L/b2-mount.log; exit 1; }

D=$M/b2t; rm -rf $D; mkdir -p $D/sub
touch $D/f1 $D/sub/f2
# and a file directly in the filesystem root, the shape the fix is about
touch $M/rootfile
sync
MDT=/tmp/lustre-mdt1
echo "=== with the filesystem up, --fid2path needs the mount; record the fixture"
ls $M | head -5

echo "=== stopping"
./llmountcleanup.sh > $L/b2-clean.log 2>&1

echo "=== --paths on the MDT (map built, non-empty)"
for arm in D F; do
	run $arm $H/arm$arm/lfs find --device $MDT --paths -type f 2>&1 |
		sort > $L/b2paths.$arm
	echo "  arm $arm: [$(tr '\n' '|' < $L/b2paths.$arm)]"
done
if diff -q $L/b2paths.D $L/b2paths.F >/dev/null; then
	ok "--paths is unchanged ($(wc -l < $L/b2paths.F) lines)"
else
	bad "--paths moved" "$(diff $L/b2paths.D $L/b2paths.F | head -5)"
fi

echo "=== a plain device scan, no naming options (the map is never built)"
for arm in D F; do
	run $arm $H/arm$arm/lfs find --device $MDT -type f 2>&1 | sort > $L/b2plain.$arm
done
if diff -q $L/b2plain.D $L/b2plain.F >/dev/null; then
	ok "a plain scan is unchanged ($(wc -l < $L/b2plain.F) lines)"
else
	bad "a plain scan moved" "$(diff $L/b2plain.D $L/b2plain.F | head -5)"
fi

echo "=== an OST scan with --paths must still be refused"
OST=/tmp/lustre-ost1
for arm in D F; do
	run $arm $H/arm$arm/lfs find --device $OST --paths -type f > $L/b2ost.$arm 2>&1
	echo "  arm $arm: rc=$? [$(head -1 $L/b2ost.$arm)]"
done
if diff -q $L/b2ost.D $L/b2ost.F >/dev/null; then
	ok "an OST refuses --paths the same way in both arms"
else
	bad "the OST answer moved" "$(diff $L/b2ost.D $L/b2ost.F | head -4)"
fi

echo "=== --paths and --fid2path together are now refused by the library"
for arm in D F; do
	out=$(run $arm $H/arm$arm/lfs find --device $MDT --paths --fid2path $M -type f 2>&1 | head -1)
	echo "  arm $arm: $out"
done
echo "=== $pass passed, $fail failed"
