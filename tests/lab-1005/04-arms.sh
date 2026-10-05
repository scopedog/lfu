#!/bin/bash
# Stage 4, as root: A/B arms for the lreview(2) fixes, old vs new
# liblustreapi on one filesystem.  Usage: sudo 04-arms.sh ldiskfs|zfs /home/<user>
#
# A1 (68417): --since on two MDTs prints an object once.
# A2 (68159, ldiskfs): an impossible --device search is refused on EVERY
#     device, not just the one it names.
FS=$1
H=$2
T=$H/lustre-release/lustre/tests
M=/mnt/lustre
fail=0
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fail=1; }

# each arm runs lfs straight out of its own tree's .libs, with that tree's
# liblustreapi -- asserted, since an installed copy would silently win
lfs_of() {	# lfs_of old|new args...
	local t=$H/lustre-release; [ $1 = old ] && t=$H/lustre-old
	shift
	LD_LIBRARY_PATH=$t/lustre/utils/.libs $t/lustre/utils/.libs/lfs "$@"
}
for a in old new; do
	t=$H/lustre-release; [ $a = old ] && t=$H/lustre-old
	LD_LIBRARY_PATH=$t/lustre/utils/.libs ldd $t/lustre/utils/.libs/lfs |
		grep -q "$t/lustre/utils/.libs/liblustreapi" ||
		{ echo "$a lfs does not load its own liblustreapi"; exit 1; }
done
echo "both arms load their own liblustreapi"

cd $T
export FSTYPE=$FS MDSCOUNT=2 OSTCOUNT=2
bash llmountcleanup.sh > /dev/null 2>&1
bash llmount.sh > /tmp/llmount.log 2>&1 || { tail -20 /tmp/llmount.log; exit 1; }
mount | grep -q " $M " || { echo "no client at $M"; exit 1; }
lfs mdts $M

# ---- A1 -----------------------------------------------------------------
u0=$(lctl --device lustre-MDT0000 changelog_register -n)
u1=$(lctl --device lustre-MDT0001 changelog_register -n)
echo "changelog users: $u0 $u1"
mkdir $M/d0
lfs mkdir -i 1 $M/d1
chmod 700 $M/d1
touch $M/d0/f1 $M/d0/f2
mv $M/d0/f1 $M/d1/
touch $M/d1/g1
mv $M/d1/g1 $M/d0/
echo x > $M/d1/f3
mv $M/d1/f3 $M/d0/f3
for i in 0 1; do
	echo "MDT000$i records: $(lfs changelog lustre-MDT000$i | wc -l)"
done
for a in old new; do
	lfs_of $a find $M --since 1h > /tmp/a1.$a 2>/tmp/a1.$a.err
	echo "$a rc=$? lines=$(wc -l < /tmp/a1.$a) dups=$(sort /tmp/a1.$a | uniq -d | wc -l)"
	sort /tmp/a1.$a | uniq -d | sed "s/^/  $a dup: /"
done
nold=$(sort /tmp/a1.old | uniq -d | wc -l)
nnew=$(sort /tmp/a1.new | uniq -d | wc -l)
[ "$nold" -gt 0 ] && pass "A1 control: old prints $nold objects twice" ||
	bad "A1 control: old printed no duplicate -- the arm proves nothing"
[ "$nnew" -eq 0 ] && pass "A1: new prints each object once" || bad "A1: new has $nnew dups"
cmp -s <(sort -u /tmp/a1.old) <(sort -u /tmp/a1.new) &&
	pass "A1: same set of paths" || bad "A1: path sets differ"
[ "$(wc -l < /tmp/a1.new)" -ge 5 ] && pass "A1: answer not empty" || bad "A1: answer too small"
lctl --device lustre-MDT0000 changelog_deregister $u0
lctl --device lustre-MDT0001 changelog_deregister $u1

# ---- A2 -----------------------------------------------------------------
if [ $FS = ldiskfs ]; then
	m0=$(losetup -r --find --show /tmp/lustre-mdt1)
	m1=$(losetup -r --find --show /tmp/lustre-mdt2)
	o0=$(losetup -r --find --show /tmp/lustre-ost1)
	o1=$(losetup -r --find --show /tmp/lustre-ost2)
	echo "loops: $m0 $m1 $o0 $o1"
	for a in old new; do
		for d in $m0 $m1; do
			lfs_of $a find --device $d --mdt lustre-MDT0001_UUID \
				--ost lustre-OST0000_UUID > /tmp/a2.out 2>&1
			echo "$a mdt+ost over $d: rc=$? $(tail -1 /tmp/a2.out)"
		done
		for d in $o0 $o1; do
			lfs_of $a find --device $d --ost lustre-OST0001_UUID \
				--stripe-count 2 > /tmp/a2.out 2>&1
			echo "$a ost+layout over $d: rc=$? $(tail -1 /tmp/a2.out)"
		done
	done 2>&1 | tee /tmp/a2.log
	# new: all four refused; old: at least one silently answered 0
	nnew=$(grep -c "^new .*rc=0 " /tmp/a2.log)
	nold=$(grep -c "^old .*rc=0 " /tmp/a2.log)
	[ "$nold" -gt 0 ] && pass "A2 control: old answered $nold impossible searches with rc=0" ||
		bad "A2 control: old refused everything -- the arm proves nothing"
	[ "$nnew" -eq 0 ] && pass "A2: new refuses on every device" ||
		bad "A2: new answered $nnew impossible searches"
	losetup -d $m0 $m1 $o0 $o1
fi

bash llmountcleanup.sh > /dev/null 2>&1
[ $fail -eq 0 ] && echo "STAGE4 ALL PASS" || echo "STAGE4 HAS FAILURES"
