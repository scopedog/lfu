#!/bin/bash
# Does "-size" actually work through --changelog --resolve?  160ab asserted it
# does; the run says otherwise, and guessing between "the predicate is broken"
# and "the assertion was wrong" is what a lab is for.
set -e
L=${LTREE:-/home/nishida/lustre-160ac}
export HOME=/root PDSH="ssh -o StrictHostKeyChecking=no -x"
export FSTYPE=ldiskfs MDSCOUNT=2 OSTCOUNT=1
cd $L/lustre/tests
./llmountcleanup.sh >/dev/null 2>&1 || true
rm -f /tmp/lustre-mdt[0-9] /tmp/lustre-ost[0-9] 2>/dev/null || true
./llmount.sh >/tmp/sizeprobe-mount.log 2>&1 || true
mount -t lustre | grep -q "on /mnt/lustre " || { tail -20 /tmp/sizeprobe-mount.log; exit 1; }

M=/mnt/lustre
MDT=$(lctl get_param -n mdc.*.mds_server_uuid 2>/dev/null | head -1 >/dev/null; echo lustre-MDT0000)
U=$(lctl --device $MDT changelog_register -n -m MARK,CREAT,CLOSE,MTIME,SATTR,TRUNC 2>/dev/null || \
    do_facet mds1 lctl --device $MDT changelog_register -n)
echo "changelog user: $U"

mkdir -p $M/szp
echo "0123456789" > $M/szp/withdata
touch $M/szp/empty
sync; sleep 2

echo "=== ls -l (what the client thinks the sizes are) ==="
ls -l $M/szp | sed 's/^/  /'
echo "=== plain find -size +0 (no changelog) ==="
lfs find $M/szp -size +0 2>&1 | sed 's/^/  /'
echo "=== changelog --resolve -type f ==="
lfs find $M --changelog all --since 5m --resolve -type f 2>&1 | head -5 | sed 's/^/  /'
echo "=== changelog --resolve -size +0 ==="
lfs find $M --changelog all --since 5m --resolve -size +0 2>&1 | head -5 | sed 's/^/  /'
echo "  (empty above = -size does not survive the changelog+resolve path)"
echo "=== changelog --resolve -size +1c ==="
lfs find $M --changelog all --since 5m --resolve -size +1c 2>&1 | head -5 | sed 's/^/  /'

lctl --device $MDT changelog_deregister $U >/dev/null 2>&1 || true
cd $L/lustre/tests && ./llmountcleanup.sh >/dev/null 2>&1 || true
echo "SIZEPROBE DONE"
