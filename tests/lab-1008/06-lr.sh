#!/bin/bash
# lab-1008 lreview checks on arm $1 (DNE ldiskfs): %Lc DoM, shard skip,
# non-cookie refused, cleared-range message
set -u
A=$1; T=/tmp/lab1008-$A; L=$T/lustre/utils/.libs/lfs
export LD_LIBRARY_PATH=/tmp/arm1008$A/lib
cd /usr/lib64/lustre/tests; export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > /tmp/lr-mount.txt 2>&1 || { echo mount failed; exit 1; }
M=/mnt/lfst
echo "== DoM %Lc (walk; getstripe says $(lfs getstripe -c $M/dom 2>/dev/null))"
$L setstripe -E 1M -L mdt $M/dom && echo x > $M/dom
echo "  getstripe -c: $(lfs getstripe -c $M/dom)"
echo "  walk %Lc: [$($L find $M/dom -printf '%Lc')]"
echo "== shards: striped dir over 2 MDTs"
$L mkdir -c 2 $M/sd; mkdir $M/plain
sync; umount $M
for i in 1 2; do
	dev=/tmp/lustre-mdt$i
	n=$(PLUGIN_DIR=/tmp/arm1008$A/lib/lustre $L find --device $dev -type d 2>/dev/null | wc -l)
	echo "  mdt$i -type d count: $n"
done
mount -t lustre $(hostname -s)@tcp:/lfst $M 2>/dev/null || bash ./llmount.sh >/dev/null 2>&1
echo "== non-cookie file"
lctl --device lfst-MDT0000 changelog_register -n >/dev/null
printf 'my notes\nline two\n' > /tmp/notes.txt
$L find $M --since-cookie /tmp/notes.txt > /dev/null; echo "  rc=$? content=[$(head -1 /tmp/notes.txt)]"
rm -f /tmp/empty.ck; : > /tmp/empty.ck
$L find $M --since-cookie /tmp/empty.ck > /dev/null 2>&1; echo "  empty cookie rc=$? header=[$(head -1 /tmp/empty.ck | cut -c1-40)]"
bash ./llmountcleanup.sh > /dev/null 2>&1; echo cleanup=$?
