#!/bin/bash
# 10-10 lab, stage 4 (as root on the clone VM): 68417 AI PS17, an unreadable
# changed object OUTSIDE the searched subtree.  Arms: slack (pushed), ai10c.
# An unprivileged user reaches --since only with debugfs readable (to list
# the MDTs), the changelog device 644 and a user_fid2path mount; a squashed
# root cannot (the MDS refuses it the changelog), which was tried first.
#   outside: old rc=13 "1 of 5 ... could not be read"; new rc=0, no message
#   under (control, proj/locked): old counts 2, new counts 1, both rc=13
exec > /tmp/lab1010-user.out 2>&1
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1010-llmount5.txt 2>&1
M=/mnt/lfst; M2=/mnt/lfst2; MDT=lfst-MDT0000
DEV=$(mount -t lustre | awk -v m=$M '$3 == m { print $1 }')
mkdir -p $M2; mount -t lustre -o user_fid2path $DEV $M2
KEEP=$(lctl --device $MDT changelog_register -n)
chmod 644 /dev/changelog-$MDT
mount -o remount,mode=755 /sys/kernel/debug; ls -ld /sys/kernel/debug
mkdir $M2/proj $M2/priv $M2/proj/locked; chown nishida $M2/proj; chmod 700 $M2/priv $M2/proj/locked
sleep 2; touch $M2/proj/mine1 $M2/priv/secret1; sync; sleep 2
for ARM in slack ai10c; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
	sudo -u nishida env LD_PRELOAD=$P/lib/liblustreapi.so.1 $T/lustre/utils/.libs/lfs find $M2/proj --since 10m -type f > /tmp/u-$ARM.txt 2> /tmp/u-$ARM.err
	echo "$ARM outside: rc=$? lines=$(tr '\n' ' ' < /tmp/u-$ARM.txt) | err: $(tr '\n' '|' < /tmp/u-$ARM.err)"
done
touch $M2/proj/locked/hidden; sync; sleep 2
for ARM in slack ai10c; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
	sudo -u nishida env LD_PRELOAD=$P/lib/liblustreapi.so.1 $T/lustre/utils/.libs/lfs find $M2/proj --since 10m -type f > /tmp/u-$ARM.txt 2> /tmp/u-$ARM.err
	echo "$ARM under: rc=$? lines=$(tr '\n' ' ' < /tmp/u-$ARM.txt) | err: $(tr '\n' '|' < /tmp/u-$ARM.err)"
done
mount -o remount,mode=700 /sys/kernel/debug
lctl --device $MDT changelog_deregister $KEEP > /dev/null; umount $M2
bash ./llmountcleanup.sh > /dev/null 2>&1; echo "cleanup rc=$?"
