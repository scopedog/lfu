#!/bin/bash
# ll_dir_ioctl rdev A/B: A = stock dir.c, B = old_decode_dev() in the V2 arm
set -u
T=/home/nishida/lustre-0918/lustre/tests; K=/home/nishida/lustre-0918/lustre/llite/lustre.ko
R=/home/nishida/rdevlab; M=/mnt/lustre
declare -A SV=([A]=$(modinfo -F srcversion $R/A.ko) [B]=$(modinfo -F srcversion $R/B.ko))
first=1
for arm in A B A B; do
	cd $T; ./llmountcleanup.sh > $R/clean.$arm.log 2>&1 || true
	if lsmod | grep -q '^lustre '; then
		for m in $(mount -t lustre | awk '{print $3}'); do umount -f $m; done
		../scripts/lustre_rmmod >> $R/clean.$arm.log 2>&1
	fi
	lsmod | grep -q '^lustre ' && { echo "lustre still loaded"; exit 1; }
	cp -p $R/$arm.ko $K
	if [ $first = 1 ]; then
		MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $R/mount.$arm.log 2>&1
	else
		NOFORMAT=1 MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $R/mount.$arm.log 2>&1
	fi
	mount -t lustre | grep -q "on $M " || { echo "NOMOUNT $arm"; tail $R/mount.$arm.log; exit 1; }
	sv=$(cat /sys/module/lustre/srcversion)
	[ "$sv" = "${SV[$arm]}" ] && echo "=== arm $arm: lustre srcversion $sv (expected)" ||
		{ echo "=== arm $arm: WRONG module $sv"; exit 1; }
	if [ $first = 1 ]; then
		rm -rf $M/rd; mkdir $M/rd
		mknod $M/rd/c10_200 c 10 200; mknod $M/rd/b8_1 b 8 1
		mknod $M/rd/c300_5 c 300 5; mknod $M/rd/c4_1048000 c 4 1048000
		first=0
	fi
	/tmp/getinfo $M/rd c10_200 b8_1 c300_5 c4_1048000 | tee $R/out.$arm.$RANDOM
	ls -l $M/rd | grep -v total | awk '{print "  ls:",$1,$5,$6,$NF}'
done
cd $T; ./llmountcleanup.sh > $R/clean.end.log 2>&1
cp -p $R/A.ko $K
echo "restored stock lustre.ko: $(modinfo -F srcversion $K)"
