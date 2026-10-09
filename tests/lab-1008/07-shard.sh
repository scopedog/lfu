#!/bin/bash
A=$1; T=/tmp/lab1008-$A; L=$T/lustre/utils/.libs/lfs
export LD_LIBRARY_PATH=/tmp/arm1008$A/lib PLUGIN_DIR=/tmp/arm1008$A/lib/lustre
cd /usr/lib64/lustre/tests; export LUSTRE=/usr/lib64/lustre FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2
env REFORMAT=yes bash ./llmount.sh > /tmp/sh-mount.txt 2>&1 || { echo mount failed; exit 1; }
M=/mnt/lfst
$L mkdir -c 2 $M/sd; mkdir $M/plain; $L getdirstripe $M/sd | head -8
sync
mount | grep lustre-mdt | cut -c1-80
for i in 1 2; do
	dev=$(mount | awk -v m=/mnt/lfst-mds$i '$3==m {print $1}')
	echo "mds$i dev=$dev"
	$L find --device $dev -type d -printf '%LF\n' 2>&1 | head -12
done
bash ./llmountcleanup.sh > /dev/null 2>&1
