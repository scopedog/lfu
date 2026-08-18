#!/bin/bash
# Stage 4: a small tree with one object per shape the record has a field for.
set -e
R=/mnt/testfs
mkdir -p $R/a/b/c $R/empty
echo hello > $R/a/plain.txt
dd if=/dev/zero of=$R/a/big.bin bs=1M count=64 status=none
[ -e $R/a/b/hardlink.txt ] || ln $R/a/plain.txt $R/a/b/hardlink.txt
ln -sf plain.txt $R/a/symlink.txt
touch $R/a/b/c/deep.txt
[ -e $R/a/striped.bin ] || lfs setstripe -c 1 -S 1M $R/a/striped.bin; dd if=/dev/zero of=$R/a/striped.bin bs=1M count=4 status=none
chown "$(id -u):$(id -g)" $R/a/plain.txt
chmod 640 $R/a/plain.txt
lfs project -p 1999 -s $R/empty 2>/dev/null || true
# volume, so that a stop mid-scan has something left to not scan, and so
# the many/ subtree is reached early by name order
mkdir -p $R/0many
for i in $(seq 1 300); do : > $R/0many/f$i; done
sync
echo "--- tree:"; find $R | sort | head -30
echo "--- object count: $(find $R | wc -l)"
echo "STAGE4 OK"
