#!/bin/bash
# Stage 13: the shared inode bitmap.  The target reads the bitmap once and
# every worker tests that one copy, so what needs proving is that concurrent
# tests agree with a single-threaded scan -- object for object, not in count.
#
# Also records peak RSS at 1 and 8 threads.  This lab's MDT is small, so the
# saving here is thousands of times smaller than on a real one; the number is
# a direction, not a headline.
set -e
L=/home/nishida/lustre-release
T=$L/lustre/tests
export LUSTRE=$L/lustre

# PLUGIN_DIR is searched before the $LUSTRE fallback, so a stale installed
# scan_ldiskfs.so is what actually loads.  Install with targets unmounted.
echo "=== sync the installed tree with the build ==="
sudo umount /mnt/testfs 2>/dev/null || true
sudo umount /mnt/ost0 /mnt/mdt0 2>/dev/null || true
sudo make -C $L install > /tmp/install13.log 2>&1 || {
	tail -5 /tmp/install13.log; exit 1; }

echo "=== remount the targets ==="
mountpoint -q /mnt/mdt0 || sudo mount -t lustre -o loop ~/img/mdt.img /mnt/mdt0
mountpoint -q /mnt/ost0 || sudo mount -t lustre -o loop ~/img/ost0.img /mnt/ost0
sleep 3
mountpoint -q /mnt/testfs || \
	sudo mount -t lustre $(hostname -i)@tcp:/testfs /mnt/testfs

# 'mount -o loop' owns its loop device and destroys it on umount, so never
# assume /dev/loop0 survived an unmount -- attach one if it did not.
MDTDEV=$(losetup -j ~/img/mdt.img | cut -d: -f1 | head -1)
OSTDEV=$(losetup -j ~/img/ost0.img | cut -d: -f1 | head -1)
[ -n "$MDTDEV" ] || MDTDEV=$(sudo losetup --find --show ~/img/mdt.img)
[ -n "$OSTDEV" ] || OSTDEV=$(sudo losetup --find --show ~/img/ost0.img)
[ -n "$MDTDEV" ] || { echo "!! no loop device for mdt.img"; exit 1; }
echo "MDT=$MDTDEV  OST=$OSTDEV"

echo
echo "=== 1. the contract tests, MDT ==="
sudo -E LUSTRE=$LUSTRE $T/llapi_scan_device_test -d $MDTDEV
echo
echo "=== 2. the contract tests, OST ==="
sudo -E LUSTRE=$LUSTRE $T/llapi_scan_device_test -d $OSTDEV

echo
echo "=== 3. the object set is identical at 1, 2, 4, 8, 16 threads ==="
# lfind has no thread option, so the lab has its own one-file harness.
gcc -o /tmp/dev_threads -I$L/include -I$L/include/uapi ~/dev_threads.c \
	-L$L/lustre/utils/.libs -llustreapi || exit 1
for j in 1 2 4 8 16; do
	sudo -E LUSTRE=$LUSTRE LD_LIBRARY_PATH=$L/lustre/utils/.libs /tmp/dev_threads $MDTDEV $j 2>/dev/null \
		| sort > /tmp/bm.j$j
	# a scan that found nothing compares equal to another that found
	# nothing, so an empty run is a failure, not a pass
	n=$(wc -l < /tmp/bm.j$j)
	[ "$n" -gt 1000 ] || { echo "  !! -j $j: only $n objects"; exit 1; }
	echo "  -j $j: $n objects"
done
[ -s /tmp/bm.j1 ] || { echo "  !! -j 1 produced nothing"; exit 1; }
fail=0
for j in 2 4 8 16; do
	if ! cmp -s /tmp/bm.j1 /tmp/bm.j$j; then
		echo "  !! -j $j differs from -j 1:"
		diff /tmp/bm.j1 /tmp/bm.j$j | head -5
		fail=1
	fi
done
[ $fail -eq 0 ] || exit 1
echo "  identical at every thread count"

echo
echo "=== 4. the bitmap is read once, not once per worker ==="
# One ext2fs_read_inode_bitmap() on the target instead of one per worker, so
# peak RSS should not climb with -j.  Before the change it climbed by
# s_inodes_count/8 per extra worker.
INODES=$(sudo dumpe2fs -h $MDTDEV 2>/dev/null | awk -F: '/Inode count/{print $2}' | tr -d ' ')
echo "  s_inodes_count=$INODES  (bitmap is $((INODES / 8 / 1024)) KB per copy)"
command -v /usr/bin/time > /dev/null || sudo dnf install -y time > /dev/null 2>&1
for j in 1 2 4 8 16; do
	rss=$(sudo -E LUSTRE=$LUSTRE LD_LIBRARY_PATH=$L/lustre/utils/.libs \
		/usr/bin/time -f '%M' /tmp/dev_threads $MDTDEV $j 2>&1 >/dev/null | tail -1)
	# /usr/bin/time missing puts its error where the number goes, and an
	# unchecked field reads as a pass
	case "$rss" in (*[!0-9]*|"") echo "  !! -j $j: bad RSS: $rss"; exit 1;; esac
	echo "  -j $j: peak RSS ${rss} KB"
done

echo
echo "ALL BITMAP CHECKS PASSED"
