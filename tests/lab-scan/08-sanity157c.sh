#!/bin/bash
# Stage 8: the in-tree test.  Builds base + both patches with tests enabled
# and runs sanity 157c, which is llapi_scan_test against a live client.
# Absolute paths: this runs under sudo, where ~ is /root.
set -e
L=/home/nishida/lustre-release
export ONLY=157c
export HOME=/root
id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas 2>/dev/null || true
chmod o+x /home/nishida /home/nishida/lustre-release

umount /mnt/testfs 2>/dev/null || true
umount /mnt/ost0 2>/dev/null || true
umount /mnt/mdt0 2>/dev/null || true
lustre_rmmod 2>/dev/null || true

cd $L
make -j"$(nproc)" > /tmp/make-157c.log 2>&1 || {
	echo "BUILD FAILED"; grep -nE 'error:' /tmp/make-157c.log | head; exit 1; }
make install > /tmp/inst-157c.log 2>&1 || { tail -5 /tmp/inst-157c.log; exit 1; }
ldconfig; depmod -a
ls -la $L/lustre/tests/llapi_scan_test | sed 's/^/  built: /'

cd $L/lustre/tests
./llmountcleanup.sh > /dev/null 2>&1 || true
FORMAT=yes bash llmount.sh > /tmp/llmount-157c.log 2>&1 || {
	echo "llmount failed"; tail -5 /tmp/llmount-157c.log; exit 1; }
bash sanity.sh > /tmp/sanity157c.log 2>&1 || true
./llmountcleanup.sh > /dev/null 2>&1 || true

echo "=== what 157c did"
sed -n '/test_157c/,/^== .*157/p' /tmp/sanity157c.log | head -40
grep -E "^(PASS|FAIL|SKIP) 157c" /tmp/sanity157c.log || echo "  157c did not report"
echo "STAGE8 DONE"
