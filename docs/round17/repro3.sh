#!/bin/bash
# The populated-target experiment.  Build the fixture ONCE, then run three
# arms against it untouched -- no destroy/recreate between arms, which is
# what invalidated the last two attempts.
L=/home/nishida/lustre-release
LFIND=$L/lustre/utils/lfind
M=/mnt/lfufs
pkill -9 -f lt-lfind 2>/dev/null; sleep 2

echo "=== fixture: an OST of lfufs at index 7, mounted, filled, then exported"
zpool import -d /dev lfu-ost1 2>/dev/null
zpool destroy lfu-ost1 2>/dev/null
zpool create -f -o cachefile=none lfu-ost1 /dev/nvme0n4 || exit 1
mkfs.lustre --ost --fsname=lfufs --index=7 --backfstype=zfs \
	--mgsnode=$(hostname -i)@tcp lfu-ost1/ost7 > /tmp/mkfs-r3.log 2>&1 || {
	tail -5 /tmp/mkfs-r3.log; exit 1; }
mkdir -p /mnt/ost7
mount -t lustre lfu-ost1/ost7 /mnt/ost7 || { echo "mount failed"; exit 1; }
sleep 8
# only this directory lands on index 7, so nothing else on the filesystem
# depends on the OST once it goes away
rm -rf $M/s7; mkdir -p $M/s7
lfs setstripe -i 7 -c 1 $M/s7 || { echo "setstripe failed"; exit 1; }
for i in $(seq 1 60); do echo "payload $i" > $M/s7/f$i; done
sync; sleep 3
echo "    objects written: $(ls $M/s7 | wc -l)"
umount /mnt/ost7; sleep 3
zpool export lfu-ost1 || { echo "export failed"; exit 1; }
echo "    exported.  fixture is now FIXED for all three arms."

arm() { # $1=label, rest=args
	local lbl=$1; shift
	echo "=== $lbl"
	timeout 90 $LFIND "$@" > /tmp/a.out 2>&1
	local rc=$?
	if (( rc == 124 )); then
		local P=$(pgrep -f lt-lfind | head -1)
		echo "    HUNG at 90s   threads=$(ls /proc/$P/task 2>/dev/null | wc -l)"
		pkill -9 -f lt-lfind; sleep 3
	else
		echo "    rc=$rc  lines=$(grep -c . /tmp/a.out)"
		head -2 /tmp/a.out | sed 's/^/      /'
	fi
	zpool list lfu-ost1 >/dev/null 2>&1 && zpool export lfu-ost1 2>/dev/null
	sleep 2
}

arm "A  control: no --fid2path  (ONE open)"            --device lfu-ost1/ost7
arm "B  --fid2path, fsname matches  (TWO opens)"       --device lfu-ost1/ost7 --fid2path $M
arm "C  same as B again"                               --device lfu-ost1/ost7 --fid2path $M
echo DONE
