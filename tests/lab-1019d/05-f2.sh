#!/bin/bash
# 10-19 lab d (root): F2 and D1 by hand on two MDTs: a --local sweep with
# --paths/--fid2path and -printf refuses once (t) or once per target (o).
set -u
OUT=/tmp/lab1019d-f2; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfsf MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfsf
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client"; exit 4; }
echo "targets: $(lctl get_param -N 'osd-*.*.mntdev' | tr '\n' ' ')"
for n in o t; do
	L=/tmp/lab1019d-$n/lustre/utils/.libs/lfs
	echo "--- arm $n ($(cat /tmp/lab1019d-$n.sha))"
	echo "+ lfs find --local --mdt --paths -printf '%p\\n'"
	$L find --local --mdt lfsf-MDT0000_UUID --paths -printf '%p\n'; echo "rc=$?"
	echo "+ lfs find --local --fid2path $M -printf '%LF\\n'"
	$L find --local --fid2path $M -printf '%LF\n'; echo "rc=$?"
	echo "+ lfs find --fsname lfsf --paths -printf '%p\\n'"
	$L find --fsname lfsf --paths -printf '%p\n'; echo "rc=$?"
	echo "+ lfs find --target MDT0000"
	$L find --target MDT0000 --type f; echo "rc=$?"
done
echo "== end $(date '+%F %T')"
bash ./llmountcleanup.sh > $OUT/clean.txt 2>&1
echo "F2 DONE"
