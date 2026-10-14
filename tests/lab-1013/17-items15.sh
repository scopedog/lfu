#!/bin/bash
# 10-13 lab (as root on the clone VM): the user's items 1 and 5, 68159.
# Usage: 17-items15.sh <old> <new>
#  1: -printf %n and %t of a striped directory on a device scan
#     old: the master inode's link count and time;  new: empty
#  5: -name under an encrypted directory on a device scan
#     old: tested against the encrypted name;  new: counted undecided
set -u
O=/tmp/lab1013-15; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst OSTCOUNT=1 LUSTRE=/usr/lib64/lustre
M=/mnt/lfst; IMG=/tmp/lfst-mdt1
run() {	# label args...
	local l=$1; shift
	for ARM in $OLD $NEW; do
		P=/tmp/arm1009$ARM; LFS=/tmp/lab1009-$ARM/lustre/utils/.libs/lfs
		LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device $IMG "$@" > $O/$l-$ARM.txt 2> $O/$l-$ARM.err
		echo "  $l $ARM rc=$? lines=$(wc -l < $O/$l-$ARM.txt) $(grep -o '[0-9]* objects could not be decided' $O/$l-$ARM.err)"
		sed 's/^/      /' $O/$l-$ARM.txt | head -4
	done
}
OLD=$1; NEW=$2

echo "--- 1: a striped directory, MDSCOUNT=2"
export MDSCOUNT=2
env REFORMAT=yes bash ./llmount.sh > $O/llmount1.txt 2>&1
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
lfs mkdir -i 0 -c 2 $M/sd; touch $M/sd/a $M/sd/b; mkdir $M/sd/sub1 $M/sd/sub2
mkdir $M/plain
echo "  walk: sd $(stat -c '%h links, ctime %Z' $M/sd); plain $(stat -c '%h links, ctime %Z' $M/plain)"
echo "  sd FID $(lfs path2fid $M/sd), plain FID $(lfs path2fid $M/plain)"
bash ./llmountcleanup.sh > $O/cleanup1.txt 2>&1
run P1 -type d -printf "%i n=%n t=%T@ a=%A@ w=%W@\n"

echo "--- 5: an encrypted directory, MDSCOUNT=1"
export MDSCOUNT=1
env REFORMAT=yes bash ./llmount.sh > $O/llmount5.txt 2>&1
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
SRC=$(mount -t lustre | awk -v m=$M '$3 == m {print $1}')
umount $M
keyctl session lab1013 bash -c '
	mode="\x00\x00\x00\x00"; raw="$(printf "\\\\x%02x" {0..63})"; size="\x40\x00\x00\x00"
	echo -n -e "${mode}${raw}${size}" | keyctl padd logon fscrypt:4242424242424242 @s > /dev/null
	mount -t lustre -o test_dummy_encryption '"$SRC $M"' || echo "  mount with the key failed"
	mkdir '"$M"'/enc && mkdir '"$M"'/enc/dir_named_clear &&
		touch '"$M"'/enc/dir_named_clear/file_named_clear '"$M"'/plainfile
	echo "  with the key: $(lsattr -d '"$M"'/enc 2>&1 | cut -c1-24) $(ls -R '"$M"' | tr "\n" " ")"
	sync; umount '"$M"'
'
bash ./llmountcleanup.sh > $O/cleanup5.txt 2>&1
run N1 -name "*named_clear*"
run N2 -type f ! -name "zzz*"
run N3 -name "plainfile"
echo "== end $(date '+%F %T')"
echo ITEMS15 DONE
