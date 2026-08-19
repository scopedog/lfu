#!/bin/bash
# Stage 9: conf-sanity test_165 -- the scanner's oracle, and the one test that
# has never run.  It stops the filesystem and diffs the device scan's FID set
# against what the client saw, so misses must be zero; then lfind --type f
# against the same scan.
#
# Runs as root (llmount insmods).  The lab's own MGS+MDT+OST must be down
# first, or conf-sanity's own targets collide with them.
set -e
L=/home/nishida/lustre-release
export HOME=/root
export ONLY=165
export SLOW=yes
id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release

umount /mnt/testfs 2>/dev/null || true
umount /mnt/ost0 2>/dev/null || true
umount /mnt/mdt0 2>/dev/null || true
lustre_rmmod 2>/dev/null || true

cd $L/lustre/tests
./llmountcleanup.sh > /dev/null 2>&1 || true

echo "=== lfind and the test binary must be where the test looks ==="
which lfind || { echo "lfind not installed"; exit 1; }
ls -la $L/lustre/tests/llapi_scan_device_test

bash conf-sanity.sh > /tmp/cs165.log 2>&1 || true
echo "=== result ==="
grep -E "^(PASS|FAIL|SKIP) 165" /tmp/cs165.log || echo "  test 165 did not report"
echo "=== what it printed ==="
sed -n '/test_165/,/PASS 165\|FAIL 165\|SKIP 165/p' /tmp/cs165.log | grep -vE "^(CMD|Waiting|pdsh)" | tail -25
./llmountcleanup.sh > /dev/null 2>&1 || true
echo "STAGE9 DONE"
