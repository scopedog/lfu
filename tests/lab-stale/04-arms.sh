#!/bin/bash
# As root: the --since-cookie purge-during-run check, old vs new liblustreapi.
# Usage: sudo 04-arms.sh /home/<user>
#
# Every arm gets a freshly formatted filesystem (MDSCOUNT=2), so neither arm
# can leave state for the other.
#
# B1  a purge on MDT0001 while MDT0000 is being read: old exits 0 and misses
#     MDT0001's files; new refuses with "purged past the cookie during this
#     run", and its cookie is unchanged.
# B2  control, no purge, default mask (CREAT + CLOSE coalesce into one
#     object): both exit 0 with the same answer -- the case the first
#     version of the fix refused.
H=$1
T=$H/lustre-release/lustre/tests
M=/mnt/lustre
CM=$T/createmany
fail=0
pass() { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fail=1; }

lfs_of() {
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

cd $T
export FSTYPE=ldiskfs MDSCOUNT=2 OSTCOUNT=2

fresh() {	# fresh <arm>: new fs, users, dirs, baseline cookie /tmp/ck.<arm>
	bash llmountcleanup.sh > /dev/null 2>&1
	FORMAT=yes bash llmount.sh > /tmp/llmount.log 2>&1 ||
		{ tail -20 /tmp/llmount.log; exit 1; }
	mount | grep -q " $M " || { echo "no client at $M"; exit 1; }
	U0=$(lctl --device lustre-MDT0000 changelog_register -n)
	U1=$(lctl --device lustre-MDT0001 changelog_register -n)
	lfs mkdir -i 0 $M/d0
	lfs mkdir -i 1 $M/d1
	touch $M/d0/base0 $M/d1/base1
	rm -f /tmp/ck.$1
	lfs_of $1 find $M --since-cookie /tmp/ck.$1 > /dev/null ||
		{ echo "$1: baseline run failed"; exit 1; }
	grep -c MDT /tmp/ck.$1 | grep -q '^2$' || { echo "$1: baseline not on 2 MDTs"; cat /tmp/ck.$1; exit 1; }
}

# ---- B2 -------------------------------------------------------------------
for a in old new; do
	fresh $a
	echo x > $M/d0/b2a
	echo x > $M/d1/b2b
	lfs_of $a find $M --since-cookie /tmp/ck.$a > /tmp/b2.$a 2>&1
	echo "B2 $a rc=$? lines=$(wc -l < /tmp/b2.$a)"
done
grep -q "purged past" /tmp/b2.new && bad "B2: new refused a run with no purge" ||
	pass "B2: no false refusal"
cmp -s <(sort /tmp/b2.old) <(sort /tmp/b2.new) && pass "B2: same answer" ||
	bad "B2: answers differ"
grep -q "d1/b2b" /tmp/b2.new && grep -q "d0/b2a" /tmp/b2.new &&
	pass "B2: answer has both new files" || bad "B2: answer misses a file"

# ---- B1 -------------------------------------------------------------------
for a in old new; do
	fresh $a
	$CM -o $M/d0/f 90000 > /dev/null	# the MDT holds ~100k inodes
	$CM -o $M/d1/g 50 > /dev/null
	echo "  MDT0001 log: $(lfs changelog lustre-MDT0001 | wc -l) records"
	sum0=$(cksum < /tmp/ck.$a)
	s=$(date +%s.%N)
	lfs_of $a find $M --since-cookie /tmp/ck.$a > /tmp/b1.$a 2>&1 &
	pid=$!
	sleep 1
	# purge MDT0001 past the anchor while MDT0000 is being read, but not
	# all of it: an emptied log is the documented blind spot
	a1=$(awk '/MDT0001/ {print $2}' /tmp/ck.$a)
	lfs changelog_clear lustre-MDT0001 $U1 $((a1 + 20))
	echo "  cleared MDT0001 to $((a1 + 20)) (anchor $a1)"
	wait $pid; rc=$?
	e=$(date +%s.%N)
	echo "$rc" > /tmp/b1.$a.rc
	echo "B1 $a rc=$rc took=$(python3 -c "print(round($e-$s,1))")s d0=$(grep -c 'd0/f' /tmp/b1.$a) d1=$(grep -c 'd1/g' /tmp/b1.$a)"
	grep -o "purged past.*" /tmp/b1.$a | cut -c1-150 | sed 's/^/  /'
	[ "$(cksum < /tmp/ck.$a)" = "$sum0" ] && echo "  $a: cookie unchanged" > /tmp/b1.$a.ck ||
		echo "  $a: cookie rewritten" > /tmp/b1.$a.ck
	cat /tmp/b1.$a.ck
done
[ "$(cat /tmp/b1.old.rc)" = 0 ] && [ "$(grep -c 'd1/g' /tmp/b1.old)" -lt 50 ] &&
	grep -q rewritten /tmp/b1.old.ck &&
	pass "B1 control: old exits 0, misses the purged MDT0001 files, advances the cookie" ||
	bad "B1 control: old did not show the silent loss -- timing?"
[ "$(cat /tmp/b1.new.rc)" != 0 ] && grep -q "purged past the cookie during this run" /tmp/b1.new &&
	grep -q unchanged /tmp/b1.new.ck &&
	pass "B1: new refuses and leaves the cookie" || bad "B1: new did not refuse"

# and the next run on that cookie is refused too, by the up-front check
lfs_of new find $M --since-cookie /tmp/ck.new > /tmp/b1.next 2>&1
rc=$?
[ $rc != 0 ] && grep -q "has purged past the cookie" /tmp/b1.next &&
	pass "B1: the next run is refused the same way" ||
	bad "B1: the next run was not refused (rc=$rc)"

bash llmountcleanup.sh > /dev/null 2>&1
[ $fail -eq 0 ] && echo "STALE ARMS ALL PASS" || echo "STALE ARMS HAVE FAILURES"
