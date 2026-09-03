#!/bin/bash
# Round 18's sanity run.  56El is NEW and 160aa was REWRITTEN -- neither has
# ever run -- so this is the first evidence either of them works.  160aa is
# also the test whose `|| error` could never fire, which is why its green
# history proves nothing and it is repeated here like the rest.
#
#   56El          lfs find -printf over a subtree that is not on Lustre (NEW)
#   160aa..160ad  lfs find --since / --changelog / --since-cookie
#   160y, 160z    lfs changelog --user / --mask (68413, 68414)
#   157c          the llapi scanner API's own test binary (68094)
#
# Run as root.  ONLY_REPEAT=2 because the round-14 cookie failure only showed
# up on a second pass, and SKIP must be 0: a skipped test proves nothing.
set -e
exec 9>/tmp/.labr18.lock
flock -n 9 || { echo "another lab run is in progress"; exit 1; }

L=${LTREE:-/home/nishida/lustre-r18}
export HOME=/root
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=${ONLY:-56El,157c,160aa,160ab,160ac,160ad,160y,160z}
export ONLY_REPEAT=${ONLY_REPEAT:-2}
export ONLY_MINUTES=${ONLY_MINUTES:-60}
export SLOW=yes FSTYPE=ldiskfs
export MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
chmod o+x /home/nishida /home/nishida/lustre-release "$L" 2>/dev/null || true

cd $L/lustre/tests
# the framework gates on the LOADED module, so read it from the node once the
# modules are up; an empty answer means "not loaded" and silently falls back
# to the userspace binary's version, which is a different artifact entirely.
echo "=== lfs version: $(lfs --version 2>&1 | head -1)"
./llmountcleanup.sh >/dev/null 2>&1 || true
rm -f /tmp/lustre-mdt[0-9] /tmp/lustre-ost[0-9] 2>/dev/null || true
echo "=== formatting and mounting (MDSCOUNT=$MDSCOUNT FSTYPE=$FSTYPE)"
./llmount.sh > /tmp/llmount-r18.log 2>&1 || true
mount -t lustre | grep -q "on /mnt/lustre " || {
	echo "llmount did not mount /mnt/lustre:"; tail -25 /tmp/llmount-r18.log; exit 1; }
V=$(lctl get_param -n version 2>/dev/null)
echo "=== loaded module version: ${V:-<EMPTY -- modules not loaded>}"
[ -n "$V" ] || { echo "no loaded version: the gate would read the userspace binary"; exit 1; }

LOG=${LOG:-/tmp/lab-r18.log}
echo "=== ONLY=$ONLY ONLY_REPEAT=$ONLY_REPEAT"
bash sanity.sh > $LOG 2>&1 || true

echo "=== verdicts ==="
grep -E "^(PASS|FAIL|SKIP) (56El|157c|160(aa|ab|ac|ad|y|z))" $LOG | sed 's/^/  /'
echo "=== tally ==="
for t in 56El 157c 160aa 160ab 160ac 160ad 160y 160z; do
	echo "  $t  PASS:$(grep -c "^PASS $t " $LOG) FAIL:$(grep -c "^FAIL $t " $LOG) SKIP:$(grep -c "^SKIP $t " $LOG)"
done
echo "  (SKIP must be 0 -- a skipped test proves nothing)"
grep -E "^ *(error|Error): " $LOG | head -10
echo "LAB RUN DONE -- full log at $LOG (filesystem left mounted for the arms)"
