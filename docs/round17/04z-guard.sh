#!/bin/bash
# Round 17: the --fid2path wrong-filesystem guard on the ZFS backend.
#
# The guard opens the target a second time, before the scan's own open.  On
# ldiskfs that is a superblock read.  On ZFS it is a pool import, and
# scan_zfs_close() drops the refcount to zero -- so it also runs
# spa_export() and kernel_fini(), and the scan that follows has to
# kernel_init() and spa_import() again in the same process.  That teardown
# and re-init is what this stage exists to exercise; nothing else does.
#
# A ZFS scan needs the pool EXPORTED, and --fid2path needs a live client
# mount of the same filesystem, so the target scanned here is OST1 while the
# filesystem stays up on the MDT and OST0.
L=~/lustre-release
LFIND=$L/lustre/utils/lfind
M=/mnt/lfufs
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "        $2"; fail=$((fail+1)); }

echo "=== the filesystem, and something to find"
sudo mkdir -p $M/g && sudo sh -c "for i in \$(seq 1 40); do echo data > $M/g/f\$i; done"
sudo $L/lustre/tests/createmany -o $M/g/m 200 > /dev/null 2>&1 || true
sync
echo "    objects under $M/g: $(sudo find $M/g -type f | wc -l)"
echo "    svname properties:"
sudo zfs get -H -o value lustre:svname lfu-mdt/mdt0 lfu-ost0/ost0 lfu-ost1/ost1 | sed 's/^/      /'

echo "=== take OST1 out of service and export its pool (the scan needs that)"
sudo umount /mnt/ost1 2>/dev/null
sleep 2
sudo zpool export lfu-ost1 || { echo "  ABORT: cannot export lfu-ost1"; exit 1; }
sudo zpool list lfu-ost1 >/dev/null 2>&1 && { echo "  ABORT: still imported"; exit 1; }
echo "    lfu-ost1 exported; client mount still up: $(mountpoint -q $M && echo yes || echo NO)"

echo
echo "=== 1. the matching fsname: guard passes, so the target is opened TWICE"
out=$(sudo $LFIND --device lfu-ost1/ost1 --fid2path $M 2>&1); rc=$?
n=$(grep -c . <<< "$out")
if grep -q "is a mount of" <<< "$out"; then
	no "1 the matching fsname was refused" "$(grep 'is a mount of' <<< "$out" | head -1)"
elif (( rc != 0 )); then
	no "1 the scan failed after the guard's own open (rc=$rc)" "$(head -3 <<< "$out")"
else
	ok "1 scan completed after the probe open/close (rc=0)"
fi
# and it has to have actually scanned: an OST names each object after the
# file that owns it, so a populated OST must yield paths
if (( n > 0 )); then
	ok "1b the scan produced $n lines, so the second import really worked"
	echo "        first: $(head -1 <<< "$out")"
else
	no "1b the scan produced nothing" "a silent empty answer is what a broken second import looks like"
fi

echo
echo "=== 2. repeat it, to show the teardown/re-init survives being done twice"
out2=$(sudo $LFIND --device lfu-ost1/ost1 --fid2path $M 2>&1); rc2=$?
n2=$(grep -c . <<< "$out2")
if (( rc2 == 0 )) && (( n2 == n )); then
	ok "2 second run agrees: rc=0, $n2 lines"
else
	no "2 second run differs (rc=$rc2, $n2 lines vs $n)" "$(head -2 <<< "$out2")"
fi

echo
echo "=== 3. the wrong filesystem: guard refuses, one open only"
sudo zpool import -d /dev lfu-ost1 2>/dev/null || true
sudo zpool destroy lfu-ost1 2>/dev/null || true
sudo zpool create -f -o cachefile=none lfu-ost1 /dev/nvme0n4 || { echo "  SKIP 3 (cannot recreate pool)"; exit 1; }
sudo mkfs.lustre --ost --fsname=otherfs --index=0 --backfstype=zfs \
	--mgsnode=$(hostname -i)@tcp lfu-ost1/ost1 > /tmp/mkfs-other.log 2>&1 || {
	echo "  SKIP 3 (mkfs failed)"; tail -5 /tmp/mkfs-other.log; exit 1; }
echo "    svname: $(sudo zfs get -H -o value lustre:svname lfu-ost1/ost1)"
sudo zpool export lfu-ost1
out3=$(sudo $LFIND --device lfu-ost1/ost1 --fid2path $M 2>&1); rc3=$?
if (( rc3 != 0 )) && grep -q "is a mount of 'lfufs', not of 'otherfs'" <<< "$out3"; then
	ok "3 the wrong filesystem is refused, and the message names both"
	echo "        $(grep 'is a mount of' <<< "$out3" | head -1 | cut -c1-150)"
else
	no "3 not refused as expected (rc=$rc3)" "${out3:-<no output>}"
fi

echo
echo "=== guard-on-zfs tally: PASS:$pass FAIL:$fail"
