#!/bin/bash
# Stage 8 (ZFS): do the two evaluators agree?
#
# Sequencing is forced here and is the reason this is one script.  The kernel
# scanner needs the target MOUNTED; the userspace ZFS scanner needs the pool
# EXPORTED (zfs-mdt-verification-2026-08-07.md §2).  So: run every filter
# through the kernel first and keep the FID sets, then take the filesystem
# down, export the pool, and replay the same filters through lfind-zfs.
DEV=lfufs-MDT0000-osd
cd ~/lfu
T=/tmp/xcheck; rm -rf $T; mkdir -p $T
FILTERS=(
	"--blocks +1G"
	"--size +1G"
	"--size +1M"
	"--stripe-count 2"
	"--stripe-count +1"
	"--pool fast"
	"--projid 1999"
	"--attrs i"
	"--name named*"
	"--comp-count +1"
	"--type d"
	"--type f"
	"--uid 0"
	"--dev-blocks +1G"
)
fids() { grep -oE '^\[0x[0-9a-f]+:0x[0-9a-f]+:0x[0-9a-f]+\]' | sort -u; }

echo "=== phase 1: through the kernel, target mounted and serving ==="
i=0
for f in "${FILTERS[@]}"; do
	i=$((i+1))
	sudo rmmod lfu_ring 2>/dev/null
	sudo insmod src/kernel/lfu_ring.ko dev=$DEV 2>/dev/null
	sudo timeout 300 build/lfind-kmdt $f /dev/lfu_scan 2>/dev/null | fids > $T/k$i
	printf '  %-24s %s objects\n' "$f" "$(grep -c . $T/k$i)"
done
sudo rmmod lfu_ring 2>/dev/null

echo "=== taking the filesystem down and exporting the pool ==="
sudo umount /mnt/lfufs; sudo umount /mnt/ost0; sudo umount /mnt/ost1; sudo umount /mnt/mdt0
sudo zpool export lfu-mdt
sudo zpool list 2>&1 | head -4

echo "=== phase 2: the same filters through lfind-zfs, pool exported ==="
i=0; agree=0; differ=0
for f in "${FILTERS[@]}"; do
	i=$((i+1))
	sudo timeout 600 build/lfind-zfs -e -p /lfu $f lfu-mdt/mdt0 2>/dev/null | fids > $T/d$i
	if cmp -s $T/k$i $T/d$i; then
		printf '  %-24s AGREE  (%s)\n' "$f" "$(grep -c . $T/k$i)"; agree=$((agree+1))
	else
		printf '  %-24s DIFFER kernel=%s device=%s\n' "$f" "$(grep -c . $T/k$i)" "$(grep -c . $T/d$i)"
		diff $T/k$i $T/d$i | head -6; differ=$((differ+1))
	fi
done
echo
echo "agree=$agree differ=$differ of ${#FILTERS[@]}"

echo "=== bringing it back up ==="
sudo zpool import -d /lfu lfu-mdt 2>&1 | tail -2
sudo mount -t lustre lfu-mdt/mdt0 /mnt/mdt0
sudo mount -t lustre lfu-ost0/ost0 /mnt/ost0
sudo mount -t lustre lfu-ost1/ost1 /mnt/ost1
sleep 5
sudo mount -t lustre $(hostname -i)@tcp:/lfufs /mnt/lfufs && df -h /mnt/lfufs | tail -1
