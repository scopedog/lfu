#!/bin/bash
# Stage 5: the ticket's acceptance list, against a real osd-zfs target.
#
#   1. the contract tests written for ldiskfs pass UNMODIFIED on ZFS
#   2. the object set is identical at 1, 2, 4, 8 and 16 threads
#   3. lfind answers predicates over the same scan
#   4. an imported pool is refused rather than read behind the kernel's back
#
# The scan needs the pool exported, so the sequence is: unmount Lustre, export,
# scan, import, remount.  That sequencing IS the open question this stage was
# built to settle, so it is exercised in both states.
set -e
L=~/lustre-release
T=$L/lustre/tests
MDT=lfu-mdt/mdt0
OST=lfu-ost0/ost0
export LUSTRE=$L/lustre

# The installed tree must match the build: PLUGIN_DIR is searched before the
# $LUSTRE fallback, so a stale installed scan_zfs.so is what actually loads,
# and an ABI-skewed plugin dies inside sb_open.  Install with everything
# unmounted -- a busy /sbin/mount.lustre kills install after a good build.
echo "=== sync the installed tree with the build ==="
sudo umount /mnt/lfufs 2>/dev/null || true
sudo umount /mnt/ost0 /mnt/ost1 /mnt/mdt0 2>/dev/null || true
sudo make -C ~/lustre-release install > /tmp/install5.log 2>&1 || {
	tail -5 /tmp/install5.log; exit 1; }

# A failed earlier run aborts mid-script and leaves the pools exported, which
# would turn the refusal check below into a scan of a legally exported pool.
# Re-establish the served state first, so the stage is idempotent.
echo "=== ensure pools are imported and targets mounted ==="
for pool in lfu-mdt lfu-ost0 lfu-ost1; do
	sudo zpool list $pool >/dev/null 2>&1 || \
		sudo zpool import -f -o cachefile=none $pool
done
mountpoint -q /mnt/mdt0 || sudo mount -t lustre lfu-mdt/mdt0 /mnt/mdt0
mountpoint -q /mnt/ost0 || sudo mount -t lustre lfu-ost0/ost0 /mnt/ost0
mountpoint -q /mnt/ost1 || sudo mount -t lustre lfu-ost1/ost1 /mnt/ost1
mountpoint -q /mnt/lfufs || { sleep 3; sudo mount -t lustre $(hostname -i)@tcp:/lfufs /mnt/lfufs; }

echo "###############################################################"
echo "# 4 first, while everything is still mounted and imported"
echo "###############################################################"
set +e
out=$(sudo -E LUSTRE=$LUSTRE $T/llapi_scan_device_test -d $MDT -o 0 2>&1)
rc=$?
set -e
echo "$out" | tail -5
if [ $rc -eq 0 ]; then
	echo "!! a scan of an IMPORTED pool SUCCEEDED -- the refusal is wrong,"
	echo "!! or the pool was not actually imported"
	exit 1
elif echo "$out" | grep -q "Device or resource busy"; then
	echo "OK: refused while imported, and says EBUSY"
else
	echo "!! refused, but not with EBUSY -- the caller cannot tell"
	echo "!! 'in service' from 'does not exist'"
	exit 1
fi

echo
echo "=== unmount Lustre and hand the pools over ==="
sudo umount /mnt/lfufs 2>/dev/null || true
sudo umount /mnt/ost0 /mnt/ost1 2>/dev/null || true
sudo umount /mnt/mdt0 2>/dev/null || true
sleep 2
sudo zpool export lfu-mdt
sudo zpool export lfu-ost0
sudo zpool export lfu-ost1
sudo zpool list 2>&1 | head -3

echo
echo "###############################################################"
echo "# 1. the contract tests, unmodified, against the ZFS MDT"
echo "###############################################################"
sudo -E LUSTRE=$LUSTRE $T/llapi_scan_device_test -d $MDT
echo "MDT CONTRACT OK"

echo
echo "###############################################################"
echo "# 1b. and against a ZFS OST"
echo "###############################################################"
sudo -E LUSTRE=$LUSTRE $T/llapi_scan_device_test -d $OST
echo "OST CONTRACT OK"

echo
echo "###############################################################"
echo "# 2. identical object set at 1, 2, 4, 8, 16 threads"
echo "###############################################################"
# the contract test covers 1/2/4/8 internally; this is the external check and
# it is what adds 16.  lfind has no thread option, so the lab has its own
# one-file harness for it.
gcc -o /tmp/dev_threads -I$L/include -I$L/include/uapi ~/dev_threads.c \
	-L$L/lustre/utils/.libs -llustreapi || exit 1
for j in 1 2 4 8 16; do
	sudo -E LUSTRE=$LUSTRE LD_LIBRARY_PATH=$L/lustre/utils/.libs \
		/tmp/dev_threads $MDT $j 2>/dev/null | sort > /tmp/zfs.j$j
	echo "  -j $j: $(wc -l < /tmp/zfs.j$j) objects"
done
[ -s /tmp/zfs.j1 ] || { echo "  !! -j 1 produced nothing"; exit 1; }
fail=0
for j in 2 4 8 16; do
	if ! cmp -s /tmp/zfs.j1 /tmp/zfs.j$j; then
		echo "  !! -j $j differs from -j 1"; fail=1
	fi
done
[ $fail -eq 0 ] && echo "THREAD IDENTITY OK: all five thread counts identical"
[ $fail -eq 0 ] || exit 1

echo
echo "###############################################################"
echo "# 3. lfind predicates over the ZFS scan"
echo "###############################################################"
all=$(wc -l < /tmp/zfs.j1)   # with --internal: the scan's full object set
sudo -E LUSTRE=$LUSTRE lfind --device $MDT --type f 2>/dev/null | sort > /tmp/zfs.typef
sudo -E LUSTRE=$LUSTRE lfind --device $MDT --type d 2>/dev/null | sort > /tmp/zfs.typed
echo "  all=$all  --type f=$(wc -l < /tmp/zfs.typef)  --type d=$(wc -l < /tmp/zfs.typed)"
[ "$(wc -l < /tmp/zfs.typef)" -gt 0 ] || { echo "  !! --type f found nothing"; exit 1; }
[ "$(wc -l < /tmp/zfs.typed)" -gt 0 ] || { echo "  !! --type d found nothing"; exit 1; }
comm -12 /tmp/zfs.typef /tmp/zfs.typed > /tmp/zfs.both
[ -s /tmp/zfs.both ] && { echo "  !! objects in BOTH f and d:"; head -3 /tmp/zfs.both; exit 1; }
echo "  files and dirs are disjoint"
sudo -E LUSTRE=$LUSTRE lfind --device $MDT --uid 65534 2>/dev/null | wc -l | \
	xargs echo "  --uid 65534 (nobody):"
sudo -E LUSTRE=$LUSTRE lfind --device $MDT --projid 1999 2>/dev/null | wc -l | \
	xargs echo "  --projid 1999:"
echo "LFIND OK"

echo
echo "=== put the pools back ==="
sudo zpool import -f -o cachefile=none lfu-mdt
sudo zpool import -f -o cachefile=none lfu-ost0
sudo zpool import -f -o cachefile=none lfu-ost1
sudo mount -t lustre lfu-mdt/mdt0 /mnt/mdt0
sudo mount -t lustre lfu-ost0/ost0 /mnt/ost0
sudo mount -t lustre lfu-ost1/ost1 /mnt/ost1
sleep 5
sudo mount -t lustre $(hostname -i)@tcp:/lfufs /mnt/lfufs
df -h /mnt/lfufs | tail -1
echo "STAGE5 OK"
