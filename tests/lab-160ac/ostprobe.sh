#!/bin/bash
# Does `lfind --local --fid2path` come back 0 on a healthy filesystem?
# Before this round an OST's O/<seq>/LAST_ID classified as a data object,
# fid2path answered -EINVAL for it, and the sweep printed every path and
# then exited non-zero.
set -e
L=/home/nishida/lustre-160ac
export HOME=/root PDSH="ssh -o StrictHostKeyChecking=no -x"
export FSTYPE=ldiskfs MDSCOUNT=2 OSTCOUNT=1
cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
./llmount.sh > /tmp/ostprobe-mount.log 2>&1 || true
mount -t lustre | grep -q "on /mnt/lustre " || { tail -20 /tmp/ostprobe-mount.log; exit 1; }
mkdir -p /mnt/lustre/ostprobe
dd if=/dev/zero of=/mnt/lustre/ostprobe/f1 bs=1M count=1 status=none
dd if=/dev/zero of=/mnt/lustre/ostprobe/f2 bs=1M count=1 status=none
sync
echo "=== lfind --local --fid2path /mnt/lustre"
set +e
lfind --local --fid2path /mnt/lustre > /tmp/ostprobe.out 2>/tmp/ostprobe.err
rc=$?
set -e
echo "exit=$rc"
echo "--- stderr"; cat /tmp/ostprobe.err
echo "--- ostprobe paths in the answer:"; grep -c ostprobe /tmp/ostprobe.out || true
echo "--- total lines: $(wc -l < /tmp/ostprobe.out)"
echo "=== the OST alone, --internal, to see the counter class"
ost=$(lctl get_param -n obdfilter.*.mntdev 2>/dev/null | head -1)
echo "ost mntdev: $ost"
set +e
lfind --device "$ost" --internal --fid2path /mnt/lustre > /tmp/ostprobe2.out 2>&1
echo "exit=$?"
set -e
tail -3 /tmp/ostprobe2.out
rm -rf /mnt/lustre/ostprobe
./llmountcleanup.sh >/dev/null 2>&1 || true
echo OSTPROBE_DONE
