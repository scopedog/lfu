#!/bin/bash
# sanity 160aa/ab/ac/ad, and the control that says 160ad is worth having.
#
# A changelog names an object by FID and fid2path answers with one of its
# names -- the first linkea entry, the one it was created under.  So a
# search rooted at the OTHER directory is answered about a name that is not
# under it.  The fix walks the links; the control cuts that back out.
#
# The same runner carries the control for 160ab's unlinked-object case,
# which is a different cut of the same file.
#
#   ARM=fixed    160aa/ab/ac/ad must all PASS, SKIP 0
#   ARM=control  160ad must FAIL (no link enumeration)
#   ARM=nofid    160ab must FAIL (no FID for an object whose name is gone)
set -e
exec 9>/tmp/.lab160ad.lock
flock -n 9 || { echo "another 12-160ad-arms.sh is running"; exit 1; }

ARM=${ARM:-fixed}
# not $HOME/...: sudo sets HOME=/root, and the tree is the user's
L=${LTREE:-/home/nishida/lustre-160ac}
export HOME=/root
export PDSH="ssh -o StrictHostKeyChecking=no -x"
export ONLY=${ONLY:-160aa,160ab,160ac,160ad}
export ONLY_REPEAT=${ONLY_REPEAT:-1}
export ONLY_MINUTES=${ONLY_MINUTES:-40}
export SLOW=yes FSTYPE=ldiskfs
export MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1

id -u runas >/dev/null 2>&1 || useradd -M runas 2>/dev/null || true
chmod o+x /home/nishida /home/nishida/lustre-release 2>/dev/null || true

cd $L
git checkout -q -- lustre/utils/liblustreapi_pfind.c
[[ "$ARM" == control ]] && python3 /home/nishida/cut-links.py "$L"
[[ "$ARM" == nofid ]] && python3 /home/nishida/cut-fidfallback.py "$L"
make -j"$(nproc)" -C lustre/utils > /tmp/arm-$ARM-build.log 2>&1 ||
	{ echo "BUILD FAILED"; grep -m5 error: /tmp/arm-$ARM-build.log; exit 1; }

cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
# a stale device file means a stale changelog index; format every time
rm -f /tmp/lustre-mdt[0-9] /tmp/lustre-ost[0-9] 2>/dev/null || true
./llmount.sh > /tmp/llmount-$ARM.log 2>&1 || true
mount -t lustre | grep -q "on /mnt/lustre " || {
	echo "llmount did not mount /mnt/lustre:"
	tail -25 /tmp/llmount-$ARM.log; exit 1; }

LOG=/tmp/lab160ad-$ARM.log
bash sanity.sh > $LOG 2>&1 || true

echo "=== ARM=$ARM verdicts ==="
grep -E "^(PASS|FAIL|SKIP) 160a" $LOG | sed 's/^/  /'
for t in 160aa 160ab 160ac 160ad; do
	echo "  $t  PASS:$(grep -c "^PASS $t" $LOG) FAIL:$(grep -c "^FAIL $t" $LOG) SKIP:$(grep -c "^SKIP $t" $LOG)"
done
grep -E "160ad.*(lost|returned)" $LOG | head -3 | sed 's/^/  /'
./llmountcleanup.sh >/dev/null 2>&1 || true
cd $L && git checkout -q -- lustre/utils/liblustreapi_pfind.c
echo "ARM=$ARM DONE -- log $LOG"
