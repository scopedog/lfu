#!/bin/bash
# 10-13 lab (as root on the clone VM): lreview run4 on 68288.  Names below an
# encrypted directory, as --paths and --fid2path print them from an MDT
# image.  The dummy key is set up as sanity-sec's setup_dummy_key() does.
# Usage: 13-enc.sh <arm>
set -u
ARM=$1; T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
O=/tmp/lab1013-enc; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=1 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
SRC=$(mount -t lustre | awk -v m=$M '$3 == m {print $1}')
umount $M
keyctl session lab1013 bash -c '
	mode="\x00\x00\x00\x00"; raw="$(printf "\\\\x%02x" {0..63})"; size="\x40\x00\x00\x00"
	echo -n -e "${mode}${raw}${size}" | keyctl padd logon fscrypt:4242424242424242 @s > /dev/null
	mount -t lustre -o test_dummy_encryption '"$SRC $M"' || echo "  mount with the key failed"
	mkdir '"$M"'/enc && mkdir '"$M"'/enc/dir_named_clear &&
		touch '"$M"'/enc/dir_named_clear/file_named_clear
	echo "  with the key: lsattr $(lsattr -d '"$M"'/enc 2>&1 | cut -c1-30); ls -R: $(ls -R '"$M"'/enc | tr "\n" " ")"
	sync; umount '"$M"'
'
mount -t lustre $SRC $M
echo "  without the key: $(ls $M/enc 2>&1 | tr '\n' ' ' | cut -c1-120)"
FID=$(lfs path2fid $M/enc 2>/dev/null)
umount $M
echo "--- the MDT image, servers stopped"
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1
LD_PRELOAD=$P/lib/liblustreapi.so.1 $LFS find --device /tmp/lfst-mdt1 --paths > $O/paths.txt 2> $O/paths.err
echo "  --paths rc=$?, lines under /enc:"
grep '^/enc' $O/paths.txt | cat -v | sed 's/^/    /' | cut -c1-140
echo "  stderr: $(cat $O/paths.err | tr '\n' ' ')"
echo "== end $(date '+%F %T')"
echo ENC DONE
