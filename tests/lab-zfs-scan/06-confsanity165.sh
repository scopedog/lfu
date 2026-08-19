#!/bin/bash
# Stage 6: conf-sanity test_165 with FSTYPE=zfs -- the same oracle the ldiskfs
# side passed, now over the ZFS backend, including the export/import the test
# learned to do for itself.
#
# Runs as root (llmount insmods).  The lab's own targets must be down first.
set -e
L=/home/nishida/lustre-release
export HOME=/root
export FSTYPE=zfs
export ONLY=165
export SLOW=yes
id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release

umount /mnt/lfufs 2>/dev/null || true
umount /mnt/ost0 /mnt/ost1 2>/dev/null || true
umount /mnt/mdt0 2>/dev/null || true
zpool export lfu-mdt 2>/dev/null || true
zpool export lfu-ost0 2>/dev/null || true
zpool export lfu-ost1 2>/dev/null || true
lustre_rmmod 2>/dev/null || true

cd $L/lustre/tests
./llmountcleanup.sh > /dev/null 2>&1 || true

which lfind || { echo "lfind not installed"; exit 1; }
ls -la $L/lustre/tests/llapi_scan_device_test

bash conf-sanity.sh > /tmp/cs165.log 2>&1 || true
echo "=== result ==="
grep -E "^(PASS|FAIL|SKIP) 165" /tmp/cs165.log || echo "  test 165 did not report"
echo "=== what it printed ==="
sed -n '/test_165/,/PASS 165\|FAIL 165\|SKIP 165/p' /tmp/cs165.log | grep -vE "^(CMD|Waiting|pdsh)" | tail -30
./llmountcleanup.sh > /dev/null 2>&1 || true
echo "STAGE6 DONE"
