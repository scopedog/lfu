#!/bin/bash
# conf-sanity test_166 on a DNE filesystem, both arms.
#
# ONLY_REPEAT is what review-dne-subtest-change uses -- it repeats a changed
# subtest inside ONE conf-sanity process, which is how autotest found this:
# iteration 1 placed the directory on MDT0000 and passed, iteration 2 placed it
# on MDT0001 and lost every file.  The probe showed why: a stock DNE filesystem
# ships a ROOT default LMV with lmv_stripe_offset -1 and max_inherit_rr 3, so
# plain mkdirs under the root round-robin MDT0,1,2,3.
#
#   ARM=pre    conf-sanity.sh reverted to the plain "mkdir -p"  -> expect FAIL
#   ARM=post   the tree as committed, mkdir_on_mdt0            -> expect PASS
set -e
L=/home/nishida/lustre-release
SRV=${SRV:-lfu-dne-srv}
ARM=${ARM:?set ARM=pre or ARM=post}
export HOME=/root
export mds_HOST=$SRV ost_HOST=$SRV mgs_HOST=$SRV
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=166
export ONLY_REPEAT=${ONLY_REPEAT:-4}
export ONLY_MINUTES=${ONLY_MINUTES:-30}
export SLOW=yes FSTYPE=ldiskfs MDSCOUNT=4 OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release
T=lustre/tests/conf-sanity.sh
cd $L
git checkout -- $T
if [ "$ARM" = pre ]; then
	perl -0pi -e 's/\tmkdir_on_mdt0 \$MOUNT\/\$tdir \|\| error "mkdir \$tdir failed"/\tmkdir -p \$MOUNT\/\$tdir/' $T
	grep -q '^	mkdir -p \$MOUNT/\$tdir' $T || { echo "PRE PATCH DID NOT APPLY"; exit 1; }
	echo "arm=pre : plain mkdir -p restored (the bug)"
else
	grep -q 'mkdir_on_mdt0 \$MOUNT/\$tdir' $T || { echo "POST ARM MISSING FIX"; exit 1; }
	echo "arm=post: mkdir_on_mdt0 (the fix)"
fi
sed -n '/# \$MOUNT and not \$DIR/,/createmany/p' $T | sed 's/^/    /'

cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
echo "=== MDSCOUNT=$MDSCOUNT ONLY_REPEAT=$ONLY_REPEAT FSTYPE=$FSTYPE"
LOG=/tmp/dne166.$ARM.log
bash conf-sanity.sh > $LOG 2>&1 || true

echo "=== per-iteration verdicts ==="
grep -E "^(PASS|FAIL|SKIP) 166|conf-sanity test 166:|FAIL: |lost [0-9]+ paths|client sees|--fid2path resolved" $LOG |
	sed 's/^/  /'
echo "=== tally ==="
echo "  PASS: $(grep -c '^PASS 166' $LOG)   FAIL: $(grep -c '^FAIL 166' $LOG)   SKIP: $(grep -c '^SKIP 166' $LOG)"
./llmountcleanup.sh >/dev/null 2>&1 || true
cd $L && git checkout -- $T
echo "ARM-$ARM DONE"
