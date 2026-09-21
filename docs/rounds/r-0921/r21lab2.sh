#!/bin/bash
# Round 21, part 2: the three arms with the first run's mistakes fixed --
# lfs find's output is not ordered, so every A/B comparison sorts first, and
# --attrs takes a name or a short letter, not a +/- sign.  Then the device
# scan, which needs the MDT stopped, so it runs last.
set -u
T=${T:-/home/nishida/lustre-0918}
M=${M:-/mnt/lustre}
D=$M/r21arms
H=/home/nishida
L=/tmp/r21lab
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
run() { local arm=$1; shift; LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"; }

mount -t lustre | grep -q "on $M " || { echo "$M is not mounted"; exit 1; }
[ -d $D/r21striped ] || { echo "the fixture is gone"; exit 1; }

########## 68094: the mask is still applied
echo "=== 68094 --attrs Immutable"
for arm in A B; do
	out=$(run $arm $H/arm$arm/lfs find $D --attrs Immutable 2>&1)
	if [ "$out" = "$D/imm" ]; then
		ok "arm $arm: --attrs Immutable finds the immutable file and nothing else"
	else
		bad "arm $arm: --attrs Immutable answered unexpectedly" "$out"
	fi
done

########## 68095: same answer, fewer RPCs
echo "=== 68095 ! --foreign, sorted comparison"
for arm in A B; do
	run $arm $H/arm$arm/lfs find $D/plain ! --foreign 2>&1 | sort > $L/f2.$arm
	run $arm $H/arm$arm/lfs find $D/plain ! --foreign -printf '%p %s\n' 2>&1 |
		sort > $L/p2.$arm
done
if diff -q $L/f2.A $L/f2.B >/dev/null; then
	ok "the answer is identical A/B ($(wc -l < $L/f2.B) paths)"
else
	bad "the answer differs A/B" "$(diff $L/f2.A $L/f2.B | head -6)"
fi
if diff -q $L/p2.A $L/p2.B >/dev/null; then
	ok "-printf prints the same thing A/B ($(wc -l < $L/p2.B) lines)"
else
	bad "-printf differs A/B" "$(diff $L/p2.A $L/p2.B | head -6)"
fi

########## 68156: the device scan
echo "=== 68156 device scan of the MDT"
# the striped directory's master is on MDT0000, which is mds1's device
MDTDEV=$(grep -m1 "mds1" $L/llmount.log 2>/dev/null | grep -o '/[^ ]*mdt1' | head -1)
[ -n "${MDTDEV:-}" ] || MDTDEV=/tmp/lustre-mdt1
echo "  MDT device: $MDTDEV"
ls -la $MDTDEV || { echo "no MDT device to scan"; exit 1; }

echo "--- stopping the filesystem"
cd $T/lustre/tests && ./llmountcleanup.sh > $L/cleanup.log 2>&1
mount -t lustre | grep -q "on $M " && { echo "still mounted"; exit 1; }

for arm in A B; do
	run $arm $H/arm$arm/lfs find --device $MDTDEV -name r21striped \
	    -printf '%s %b\n' > $L/dev.$arm 2>&1
	echo "  arm $arm: $(cat $L/dev.$arm | tr '\n' '|')"
done
if diff -q $L/dev.A $L/dev.B >/dev/null; then
	bad "the device scan answers the same in both arms" "$(cat $L/dev.B)"
else
	ok "the device scan changed: A=$(head -1 $L/dev.A) B=$(head -1 $L/dev.B)"
fi
# and an unstriped directory must be unaffected
for arm in A B; do
	run $arm $H/arm$arm/lfs find --device $MDTDEV -name d7 \
	    -printf '%s %b\n' > $L/devplain.$arm 2>&1
done
if diff -q $L/devplain.A $L/devplain.B >/dev/null; then
	ok "an unstriped directory answers the same in both arms ($(head -1 $L/devplain.B))"
else
	bad "an unstriped directory changed" "$(diff $L/devplain.A $L/devplain.B | head -4)"
fi
# a regular file must be unaffected too
for arm in A B; do
	run $arm $H/arm$arm/lfs find --device $MDTDEV -name one \
	    -printf '%s %b\n' > $L/devfile.$arm 2>&1
done
if diff -q $L/devfile.A $L/devfile.B >/dev/null; then
	ok "a regular file answers the same in both arms ($(head -1 $L/devfile.B))"
else
	bad "a regular file changed" "$(diff $L/devfile.A $L/devfile.B | head -4)"
fi

echo "=== $pass passed, $fail failed"
exit $((fail > 0))
