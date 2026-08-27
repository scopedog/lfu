#!/bin/bash
# Stage 4: conf-sanity test_166 on a DNE filesystem, the configuration that
# review-dne-subtest-change runs and that every previous lab for this test
# lacked.  MDSCOUNT=4, so a plain mkdir can place the test directory on an MDT
# other than the one the test scans.
#
# Two arms, both run twice, because autotest's failure appeared on the SECOND
# iteration -- review-dne-subtest-change repeats a changed subtest, and the
# first iteration placed the directory on MDT0000 and passed.
#
#   ARM=pre    conf-sanity.sh patched back to the plain "mkdir -p"  -> expect FAIL
#   ARM=post   the tree as committed, mkdir_on_mdt0                 -> expect PASS
set -e
L=/home/nishida/lustre-release
SRV=${SRV:-lfu-dne-srv}
ARM=${ARM:?set ARM=pre or ARM=post}
ITERS=${ITERS:-2}
export HOME=/root
export mds_HOST=$SRV ost_HOST=$SRV mgs_HOST=$SRV
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=166
export SLOW=yes FSTYPE=ldiskfs
export MDSCOUNT=4
export OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release
cd $L/lustre/tests

T=lustre/tests/conf-sanity.sh
cd $L
git checkout -- $T
if [ "$ARM" = pre ]; then
	# put the bug back: exactly the line the fix replaced
	perl -0pi -e 's/\tmkdir_on_mdt0 \$MOUNT\/\$tdir \|\| error "mkdir \$tdir failed"/\tmkdir -p \$MOUNT\/\$tdir/' $T
	grep -q 'mkdir -p \$MOUNT/\$tdir' $T || { echo "PRE-ARM PATCH DID NOT APPLY"; exit 1; }
	echo "arm=pre : reverted to plain mkdir -p"
else
	grep -q 'mkdir_on_mdt0 \$MOUNT/\$tdir' $T || { echo "POST ARM MISSING FIX"; exit 1; }
	echo "arm=post: mkdir_on_mdt0 in place"
fi
cd $L/lustre/tests
./llmountcleanup.sh > /dev/null 2>&1 || true

echo "=== config: MDSCOUNT=$MDSCOUNT OSTCOUNT=$OSTCOUNT FSTYPE=$FSTYPE iters=$ITERS"
ssh -o StrictHostKeyChecking=no root@$SRV "hostname; which lfind" || exit 1

pass=0; fail=0
for i in $(seq 1 $ITERS); do
	echo "########## iteration $i/$ITERS (arm=$ARM) ##########"
	bash conf-sanity.sh > /tmp/dne166.$ARM.$i.log 2>&1 || true
	r=$(grep -E "^(PASS|FAIL|SKIP) 166" /tmp/dne166.$ARM.$i.log | head -1)
	echo "  result: ${r:-<no report>}"
	case "$r" in
		PASS*) pass=$((pass+1));;
		FAIL*) fail=$((fail+1));;
	esac
	# where did the directory actually land?  the whole question.
	grep -oE "d166\.conf-sanity" /tmp/dne166.$ARM.$i.log >/dev/null && true
	grep -E "client sees|--fid2path resolved|lost [0-9]+ paths|FAIL: " \
		/tmp/dne166.$ARM.$i.log | head -5 | sed 's/^/  /'
done
echo "=== ARM=$ARM SUMMARY: pass=$pass fail=$fail of $ITERS"
cd $L && git checkout -- $T
./lustre/tests/llmountcleanup.sh > /dev/null 2>&1 || true
echo "STAGE4-$ARM DONE"
