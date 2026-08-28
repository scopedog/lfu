#!/bin/bash
# sanity 160ac under ONLY_REPEAT, instrumented to print what the stale-anchor
# check actually sees.
#
# The failure is "a stale cookie should be refused" -- lfs find returned 0
# where it had to refuse.  Three readings fit that equally well and need
# opposite fixes, so the probe prints the one number that separates them:
# the index of the oldest surviving changelog record, against the cookie's 1.
#
#   H1  log is empty         -> find_cl_oldest leaves *oldest = 0, 0 > 1 false
#   H2  first rec has no     -> find_cl_first_cb stores 0 explicitly, same
#       LLAPI_SCAN_EVENT
#   H3  oldest record IS 1   -> 1 > 1 false; the guard is RIGHT and the test's
#                               premise ("index 1 is always stale") is wrong
#
# H1/H2 are defects in 68419.  H3 is a defect in the test.  The record count
# and the first record's index tell them apart in one run.
set -e
L=/home/nishida/lustre-release
export HOME=/root
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=160aa,160ab,160ac
export ONLY_REPEAT=${ONLY_REPEAT:-2}
export ONLY_MINUTES=${ONLY_MINUTES:-30}
export SLOW=yes FSTYPE=ldiskfs
# review-dne-subtest-change is DNE; the Janitor's passing run was DNE too, so
# this is for fidelity, not because DNE is suspected.
export MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release
T=$L/lustre/tests/sanity.sh
cd $L
git checkout -- lustre/tests/sanity.sh

python3 - "$T" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''	# an anchor older than the oldest surviving record is refused
	echo "$(facet_svc $SINGLEMDS) 1" > $ck
	$LFS find $DIR/$tdir --since-cookie $ck -type f &> /dev/null &&
		error "a stale cookie should be refused"
'''
new = '''	# an anchor older than the oldest surviving record is refused
	local mdt0=$(facet_svc $SINGLEMDS)
	local nrec=$($LFS changelog $mdt0 2>/dev/null | grep -c .)
	echo "PROBE: mdt=$mdt0 surviving_records=$nrec"
	echo "PROBE: cookie_was: $(cat $ck | tr '\\n' '|')"
	do_facet $SINGLEMDS $LCTL get_param -n mdd.$mdt0.changelog_users 2>&1 |
		sed 's/^/PROBE: users: /'
	$LFS changelog $mdt0 2>&1 | head -2 | sed 's/^/PROBE: oldest_rec: /'
	echo "$mdt0 1" > $ck
	local rc160=0
	$LFS find $DIR/$tdir --since-cookie $ck -type f > /tmp/probe160.out 2>&1 ||
		rc160=$?
	echo "PROBE: stale_find_exit=$rc160"
	sed 's/^/PROBE: stale_find_out: /' /tmp/probe160.out
	(( rc160 == 0 )) &&
		error "a stale cookie should be refused"
'''
if old not in s:
    sys.exit("PROBE PATCH DID NOT MATCH -- 160ac's stale block has changed")
open(p, 'w').write(s.replace(old, new))
print("probe inserted")
PY

cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
echo "=== MDSCOUNT=$MDSCOUNT ONLY_REPEAT=$ONLY_REPEAT ONLY=$ONLY"
LOG=/tmp/lab160ac.log
bash sanity.sh > $LOG 2>&1 || true

echo "=== the probe ==="
grep -E "^PROBE:" $LOG | sed 's/^/  /'
echo "=== verdicts ==="
grep -E "^(PASS|FAIL|SKIP) 160(aa|ab|ac)" $LOG | sed 's/^/  /'
echo "=== tally ==="
for t in 160aa 160ab 160ac; do
	echo "  $t  PASS:$(grep -c "^PASS $t" $LOG) FAIL:$(grep -c "^FAIL $t" $LOG) SKIP:$(grep -c "^SKIP $t" $LOG)"
done
echo "  (SKIP must be 0 -- a skipped test proves nothing)"
./llmountcleanup.sh >/dev/null 2>&1 || true
cd $L && git checkout -- lustre/tests/sanity.sh
echo "PROBE RUN DONE -- full log at $LOG"
