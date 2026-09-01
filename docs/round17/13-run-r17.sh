#!/bin/bash
# Round 17's verification run.  Run as root.
#
#   160aa..160ad  lfs find --since / --changelog / --since-cookie
#   160y, 160z    lfs changelog --user / --mask (68413, 68414)
#   157c          the llapi scanner API's own test binary (68094)
#
# ONLY_REPEAT=2 because the round-14 cookie failure only showed up on a second
# pass, and SKIP must be 0: a skipped test proves nothing.
set -e
exec 9>/tmp/.lab160ac.lock
flock -n 9 || { echo "another lab run is in progress"; exit 1; }

L=${LTREE:-/home/nishida/lustre-160ac}
export HOME=/root
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=${ONLY:-157c,160aa,160ab,160ac,160ad,160y,160z}
export ONLY_REPEAT=${ONLY_REPEAT:-2}
export ONLY_MINUTES=${ONLY_MINUTES:-60}
export SLOW=yes FSTYPE=ldiskfs
export MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
chmod o+x /home/nishida /home/nishida/lustre-release 2>/dev/null || true

cd $L/lustre/tests
echo "=== lfs version: $(lfs --version 2>&1 | head -1)"
./llmountcleanup.sh >/dev/null 2>&1 || true
rm -f /tmp/lustre-mdt[0-9] /tmp/lustre-ost[0-9] 2>/dev/null || true
echo "=== formatting and mounting (MDSCOUNT=$MDSCOUNT FSTYPE=$FSTYPE)"
./llmount.sh > /tmp/llmount-r17.log 2>&1 || true
mount -t lustre | grep -q "on /mnt/lustre " || {
	echo "llmount did not mount /mnt/lustre:"; tail -25 /tmp/llmount-r17.log; exit 1; }

LOG=${LOG:-/tmp/lab-r17.log}
echo "=== ONLY=$ONLY ONLY_REPEAT=$ONLY_REPEAT"
bash sanity.sh > $LOG 2>&1 || true

echo "=== verdicts ==="
grep -E "^(PASS|FAIL|SKIP) (157c|160(aa|ab|ac|ad|y|z))" $LOG | sed 's/^/  /'
echo "=== tally ==="
for t in 157c 160aa 160ab 160ac 160ad 160y 160z; do
	echo "  $t  PASS:$(grep -c "^PASS $t " $LOG) FAIL:$(grep -c "^FAIL $t " $LOG) SKIP:$(grep -c "^SKIP $t " $LOG)"
done
echo "  (SKIP must be 0 -- a skipped test proves nothing)"
grep -E "^ *(error|Error): " $LOG | head -10
echo "LAB RUN DONE -- full log at $LOG"
