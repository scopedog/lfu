#!/bin/bash
# conf-sanity 305: lfs find over a target that is in service, the case the
# 09-22 lreview on LU-20722 said was untested.
set -e
exec 9>/tmp/.labonce.lock
flock -n 9 || { echo "another lab run is in progress"; exit 1; }
L=${LTREE:-/home/nishida/lustre-0918}
export HOME=/root PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=305 SLOW=yes FSTYPE=ldiskfs MDSCOUNT=2 OSTCOUNT=1
cd "$L/lustre/tests"
id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
chmod o+x /home/nishida "$L" 2>/dev/null || true
./llmountcleanup.sh >/dev/null 2>&1 || true
umount -f /mnt/lustre-mds1 /mnt/lustre-mds2 /mnt/lustre-ost1 2>/dev/null || true
LOG=/tmp/conf305.log
echo "lfs: $($L/lustre/utils/lfs --version 2>&1 | head -1)"
echo "plugin: $(md5sum /usr/lib64/lustre/scan_osd_kernel.so)"
bash conf-sanity.sh > $LOG 2>&1 || true
grep -E "^(PASS|FAIL|SKIP) 305" $LOG | sed 's/^/  /'
echo "  PASS:$(grep -c '^PASS 305 ' $LOG) FAIL:$(grep -c '^FAIL 305 ' $LOG) SKIP:$(grep -c '^SKIP 305 ' $LOG)"
grep -E "^ *(error|Error|skip): " $LOG | head -8
grep -E "a scan of the mounted" $LOG | head -2
echo "CONF305 DONE: $LOG"
