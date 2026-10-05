#!/bin/bash
# A metadata_csum image, one inode's i_mtime flipped, scanned the way
# libscan_ldiskfs's worker opens it: without (0) and with (1) the fix that
# clears EXT2_FLAG_IGNORE_CSUM_ERRORS on the worker handle.  Needs
# libext2fs-dev, mkfs.ext4 and debugfs; no root.
set -e
D=$(mktemp -d); cd $D
gcc -o s $(dirname $(readlink -f $0))/scan_csum.c -lext2fs -lcom_err
truncate -s 64M img && mkfs.ext4 -q -F -O metadata_csum,^has_journal -I 1024 img
for i in 1 2 3 4 5; do echo "data $i" > f$i; debugfs -w -R "write f$i f$i" img >/dev/null 2>&1; done
echo "== clean";  ./s img 0 | tail -1; ./s img 1 | tail -1
cp img torn
blk=$(debugfs -R "imap /f3" torn 2>/dev/null | sed -n 's/.*located at block \([0-9]*\).*/\1/p')
off=$(debugfs -R "imap /f3" torn 2>/dev/null | sed -n 's/.*offset \(0x[0-9a-f]*\).*/\1/p')
bs=$(dumpe2fs -h torn 2>/dev/null | awk -F: '/^Block size/{gsub(/ /,"",$2); print $2}')
printf '\x5a' | dd of=torn bs=1 seek=$((blk * bs + off + 0x10)) conv=notrunc status=none
echo "== one torn inode"; ./s torn 0 | tail -1; ./s torn 1 | tail -1
