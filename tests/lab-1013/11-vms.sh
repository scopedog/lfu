#!/bin/bash
# 10-13 lab (as root on the clone VM), ldiskfs.  Usage: 11-vms.sh <old> <new>
#  c: item 6's skip path.  --mdt 1 against MDT0's image: the target cannot
#     match.  old (n1013h): the caller's counters stay 999;  new: zeros
#  1: item 1.  An MDT formatted with 128-byte inodes has no room for a birth
#     time.  A walk over the mount is the reference.
#  b: lreview run4 on 68288.  A client mounted with test_dummy_encryption
#     creates encrypted names; --paths on the MDT image prints what?
set -u
O=/tmp/lab1013-vm; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre OSTCOUNT=1 MDSCOUNT=1
OLD=$1; NEW=$2
for ARM in $OLD $NEW; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
	gcc -O2 -o /tmp/fstats-$ARM /tmp/fstats.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || echo "cc fstats $ARM failed"
done

echo "--- c + 1: FSNAME=lfsb, MDT inodes of 128 bytes"
export FSNAME=lfsb
env REFORMAT=yes MDS_FS_MKFS_OPTS="-I 128" bash ./llmount.sh > $O/llmount-b.txt 2>&1
M=/mnt/lfsb
if mount -t lustre | grep -q "on $M "; then
	IMG=$(mount | awk '/lfsb-MDT0000|mdt1/ && / type lustre/ {print $1; exit}')
	[ -z "$IMG" ] && IMG=/tmp/lfsb-mdt1
	mkdir $M/d; touch $M/d/f1 $M/d/f2 $M/d/f3; sync
	echo "inode size $(dumpe2fs -h /tmp/lfsb-mdt1 2>/dev/null | awk -F: '/^Inode size/ {print $2}' | tr -d ' ')"
	echo "walk over the mount:"
	for pred in "-btime +30" "! -btime +30" "-btime -30" "! -btime -30"; do
		echo "  walk [$pred]: $(lfs find $M/d -type f $pred 2>&1 | wc -l) lines"
	done
	echo "  stat %W of f1: $(stat -c '%W %w' $M/d/f1)"
	bash ./llmountcleanup.sh > $O/cleanup-b.txt 2>&1
	for ARM in $OLD $NEW; do
		T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
		for pred in "-btime +30" "! -btime +30" "-btime -30" "! -btime -30"; do
			out=$(LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device /tmp/lfsb-mdt1 -type f $pred 2>$O/err)
			echo "  1 $ARM scan [$pred]: $(echo -n "$out" | grep -c .) lines; $(grep -o '[0-9]* objects could not be decided' $O/err)"
		done
	done
else
	echo "  128-byte inodes did not mount: $(grep -i -m3 'error\|fail\|inode' $O/llmount-b.txt | tr '\n' '|')"
	bash ./llmountcleanup.sh > $O/cleanup-b.txt 2>&1
fi

echo "--- b: FSNAME=lfst, client with test_dummy_encryption"
export FSNAME=lfst
env REFORMAT=yes bash ./llmount.sh > $O/llmount-t.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
SRC=$(mount -t lustre | awk -v m=$M '$3 == m {print $1}')
umount $M && mount -t lustre -o test_dummy_encryption $SRC $M || echo "  remount with test_dummy_encryption failed"
mkdir $M/enc && mkdir $M/enc/dir_named_clear && touch $M/enc/dir_named_clear/file_named_clear
echo "  lsattr: $(lsattr -d $M/enc 2>&1 | cut -c1-40); walk: $(lfs find $M/enc | tr '\n' ' ')"
umount $M; mount -t lustre $SRC $M
echo "  remounted without the option: $(ls $M/enc 2>&1 | tr '\n' ' ')"
for ARM in $OLD $NEW; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	echo "c $ARM ($(cat /tmp/lab1009-$ARM.sha)) skip: $(/tmp/fstats-$ARM /tmp/lfst-mdt1 lfst-MDT0001_UUID 2>&1 >/dev/null)"
	echo "c $ARM ($(cat /tmp/lab1009-$ARM.sha)) plain: $(/tmp/fstats-$ARM /tmp/lfst-mdt1 2>&1 >/dev/null)"
done
sync
bash ./llmountcleanup.sh > $O/cleanup-t.txt 2>&1
for ARM in $OLD $NEW; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device /tmp/lfst-mdt1 --paths > $O/b-$ARM.txt 2> $O/b-$ARM.err
	echo "  b $ARM --paths rc=$?: $(grep '^/enc' $O/b-$ARM.txt | cat -v | tr '\n' ' ' | cut -c1-300) | $(tail -2 $O/b-$ARM.err | tr '\n' ' ')"
done
echo "== end $(date '+%F %T')"
echo VMS DONE
