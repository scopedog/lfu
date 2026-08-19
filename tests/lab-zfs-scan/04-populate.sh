#!/bin/bash
# Stage 4: one file per shape the record has a field for, then volume.
#
# The big xattr is the point of the ZFS run: a value too large for the SA area
# spills to the xattr directory, which is the path with no ldiskfs equivalent
# in the prototype and the one the new backend had to grow.
set -e
M=/mnt/lfufs
sudo mkdir -p $M/shapes && sudo chmod 777 $M $M/shapes
cd $M/shapes

echo "=== shapes ==="
dd if=/dev/urandom of=plain bs=1M count=4 status=none
sudo -u nobody touch owned-by-nobody 2>/dev/null || { touch owned-by-nobody; sudo chown 65534 owned-by-nobody; }
lfs setstripe -c 2 striped2 && dd if=/dev/zero of=striped2 bs=1M count=8 status=none
ln plain hardlinked                      # 2-entry linkea
mkdir adir && touch adir/child
ln -s plain asymlink
touch projid-file && sudo lfs project -p 1999 projid-file 2>/dev/null || true
touch immutable-file && sudo chattr +i immutable-file 2>/dev/null || true

# a layout wide enough that the EA cannot sit in the SA bonus: this is the
# spill path, and on ldiskfs it is the external EA block
lfs setstripe -c -1 -S 64K wide 2>/dev/null || lfs setstripe -c 2 wide
sudo setfattr -n trusted.bigea -v "$(python3 -c 'print("x"*3000)')" wide 2>/dev/null || true
getfattr -m - -d --absolute-names wide 2>/dev/null | head -3 || true

echo "=== volume ==="
mkdir -p $M/many
~/lustre-release/lustre/tests/createmany -m $M/many/f 20000 > /tmp/createmany.log 2>&1 || \
	{ tail -3 /tmp/createmany.log; exit 1; }
tail -1 /tmp/createmany.log

echo "=== what the client sees ==="
lfs df -i /mnt/lfufs | head -3
find $M -printf "" 2>/dev/null; echo "files under $M: $(find $M | wc -l)"
echo "STAGE4 OK"
