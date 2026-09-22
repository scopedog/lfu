#!/bin/bash
# The rig's modules are 2.17.57, below the 2.17.58 guard every test in this
# block carries, so 305 skips.  Relax the guard IN THE WORKING COPY ONLY --
# the committed test keeps it -- to find out whether the test body works
# before the Test-Parameters line sends it to Maloo.  Restored at exit.
set -e
exec 9>/tmp/.labonce.lock
flock -n 9 || { echo "another lab run is in progress"; exit 1; }
L=${LTREE:-/home/nishida/lustre-0918}
export HOME=/root PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=305 SLOW=yes FSTYPE=ldiskfs MDSCOUNT=2 OSTCOUNT=1
cd "$L/lustre/tests"
cp -f conf-sanity.sh /tmp/conf-sanity.sh.orig
trap 'cp -f /tmp/conf-sanity.sh.orig '"$L"'/lustre/tests/conf-sanity.sh' EXIT
python3 - "$L/lustre/tests/conf-sanity.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''	(( MDS1_VERSION >= $(version_code 2.17.58) )) ||
		skip "Need MDS >= 2.17.58 for a scan of a target in service"
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, '\t# guard relaxed for this local run only\n'))
PY
id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
chmod o+x /home/nishida "$L" 2>/dev/null || true
./llmountcleanup.sh >/dev/null 2>&1 || true
umount -f /mnt/lustre-mds1 /mnt/lustre-mds2 /mnt/lustre-ost1 2>/dev/null || true
LOG=/tmp/conf305b.log
bash conf-sanity.sh > $LOG 2>&1 || true
grep -E "^(PASS|FAIL|SKIP) 305" $LOG | sed 's/^/  /'
sed -n '/conf-sanity test 305/,/^\(PASS\|FAIL\|SKIP\) 305/p' $LOG | tail -25
echo "CONF305B DONE: $LOG"
