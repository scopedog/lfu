#!/bin/bash
# Stage 4: conf-sanity test_166 with the MDS on another node.
#
# This is the layout the test needs and a single-node lab cannot give: the
# runner is a client, mds_HOST/ost_HOST are the server, so $MOUNT exists here
# and not there.  Before the fix the test passed --fid2path $MOUNT to lfind on
# the MDS and failed with "cannot open '/mnt/lustre' to resolve FIDs".
set -e
L=/home/nishida/lustre-release
SRV=${SRV:-lfu-166-srv}
export HOME=/root
export mds_HOST=$SRV
export ost_HOST=$SRV
export mgs_HOST=$SRV
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=${ONLY:-166}
export SLOW=yes
export FSTYPE=ldiskfs
export MDSCOUNT=1
export OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release
cd $L/lustre/tests
./llmountcleanup.sh > /dev/null 2>&1 || true

echo "=== facets ==="
echo "runner  : $(hostname)"
echo "mds_HOST: $mds_HOST"
ssh -o StrictHostKeyChecking=no root@$SRV "hostname; which lfind" || exit 1

bash conf-sanity.sh > /tmp/cs166.log 2>&1 || true
echo "=== result ==="
grep -E "^(PASS|FAIL|SKIP) $ONLY" /tmp/cs166.log || echo "  test $ONLY did not report"
echo "=== what it printed ==="
sed -n "/test_$ONLY/,/PASS $ONLY\|FAIL $ONLY\|SKIP $ONLY/p" /tmp/cs166.log |
	grep -vE "^(CMD|Waiting|pdsh)" | tail -40
./llmountcleanup.sh > /dev/null 2>&1 || true
echo "STAGE4 DONE"
