#!/bin/bash
# Round 15: the device-scanner half.  conf-sanity 165 and 166 are the two
# cases that exercise llapi_scan_device() and lfind, which is where this
# round's scan_classify() and --fid2path changes live.
set -e
exec 9>/tmp/.lab160ac.lock
flock -n 9 || { echo "another lab run is in progress"; exit 1; }

L=${LTREE:-/home/nishida/lustre-160ac}
export HOME=/root
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=${ONLY:-165,166}
export ONLY_REPEAT=${ONLY_REPEAT:-2}
export ONLY_MINUTES=${ONLY_MINUTES:-60}
export SLOW=yes FSTYPE=ldiskfs
export MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
LOG=${LOG:-/tmp/lab-r15-conf.log}
echo "=== ONLY=$ONLY ONLY_REPEAT=$ONLY_REPEAT (conf-sanity formats its own)"
bash conf-sanity.sh > $LOG 2>&1 || true

echo "=== verdicts ==="
grep -E "^(PASS|FAIL|SKIP) 16[56]" $LOG | sed 's/^/  /'
for t in 165 166; do
	echo "  $t  PASS:$(grep -c "^PASS $t " $LOG) FAIL:$(grep -c "^FAIL $t " $LOG) SKIP:$(grep -c "^SKIP $t " $LOG)"
done
grep -E "^ *(error|Error): " $LOG | head -10
./llmountcleanup.sh >/dev/null 2>&1 || true
echo "CONF RUN DONE -- full log at $LOG"
