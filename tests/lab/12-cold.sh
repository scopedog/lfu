#!/bin/bash
# Stage 12: COLD.  The ritual is the documented one: unmount everything ->
# drop_caches -> remount -> take the FIRST pass only, because a second pass is
# warm by definition.  One full cycle per measurement.
#
# Two questions: (a) does readahead still earn its keep cold, now that we know
# it costs up to 90% warm; (b) does pushing a filter down change the cold rate,
# or is cold simply bytes off the device regardless.
#
# Storage note: this MDT is a 20 GiB loop FILE on a GCP pd-balanced disk, not
# the local NVMe of the 2026-08-16 cold runs.  Absolute rates here are not
# comparable to that document; the comparisons WITHIN this run are.
set -e
cd ~/lfu
NID=$(sudo lctl list_nids | head -1)

cold_cycle() {   # cold_cycle  -> unmount, drop, remount
	sudo umount /mnt/testfs 2>/dev/null || true
	for i in 0 1 2 3; do sudo umount /mnt/testfs-ost$i 2>/dev/null || true; done
	sudo umount /mnt/testfs-mdt0 2>/dev/null || true
	sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'; sleep 2
	sudo mount -t lustre -o loop /lustre/mdt.img /mnt/testfs-mdt0
	for i in 0 1 2 3; do sudo mount -t lustre -o loop /lustre/ost$i.img /mnt/testfs-ost$i; done
	sleep 3
}

par_cold() {     # par_cold <bp> <ra> <j>
	local bp=$1 ra=$2 j=$3
	cold_cycle
	echo "$bp" | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_blockparse >/dev/null
	echo "$ra" | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_ra_blocks >/dev/null
	echo 1 | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_noverify >/dev/null
	sudo dmesg -C
	sudo insmod src/kernel/lfu_par.ko dev=testfs-MDT0000-osd nthreads=$j private=1 recattr=1 2>/dev/null || true
	sudo rmmod lfu_par 2>/dev/null || true
	local line=$(sudo dmesg | grep 'lfu_par: dev=' | tail -1)
	local rate=$(echo "$line" | grep -oE 'rate=[0-9]+' | cut -d= -f2)
	local objs=$(echo "$line" | grep -oE 'objects=[0-9]+' | cut -d= -f2)
	printf 'COLD lfu_par bp=%s ra=%-4s j%-2s objects=%-8s rate=%s/s\n' \
		"$bp" "$ra" "$j" "${objs:-?}" "${rate:-?}"
}

ring_cold() {    # ring_cold <label> <args...>
	cold_cycle
	echo 1 | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_blockparse >/dev/null
	echo 32 | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_ra_blocks >/dev/null
	sudo rmmod lfu_ring 2>/dev/null || true
	sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
	local label="$1"; shift
	local out
	out=$(sudo timeout 900 build/lfu-scan-kmdt -q "$@" /dev/lfu_scan 2>&1)
	local r=$(echo "$out" | grep -oE 'rate *: *[0-9]+' | grep -oE '[0-9]+$')
	local sc=$(echo "$out" | grep -oE 'objects scanned : [0-9]+' | grep -oE '[0-9]+$')
	local k=$(echo "$out" | grep '^kernel:' | grep -oE 'xattr: inline=[0-9]+ external=[0-9]+')
	printf 'COLD ring %-30s scanned=%-8s rate=%-9s %s\n' "$label" "${sc:-?}" "${r:-?}" "$k"
	sudo rmmod lfu_ring 2>/dev/null || true
}

echo "=== is readahead still worth it cold? (lfu_par, first pass) ==="
par_cold 1 0   1
par_cold 1 32  1
par_cold 1 256 1
par_cold 1 0   4
par_cold 1 256 4
par_cold 0 32  1

echo
echo "=== does pushing a filter down change the cold rate? (lfu_ring) ==="
ring_cold "no filter"
ring_cold "--uid 4242 (tier 0, rejects all)"  --uid 4242
ring_cold "--blocks +1G (tier 1)"             --blocks +1G
ring_cold "--name 'zzz*' (tier 1, every obj)" --name 'zzz*'

echo
echo "=== restore, remount the client ==="
echo 1  | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_blockparse >/dev/null
echo 32 | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_ra_blocks >/dev/null
echo 0  | sudo tee /sys/module/osd_ldiskfs/parameters/lfu_noverify >/dev/null
sudo mount -t lustre "$NID":/testfs /mnt/testfs 2>/dev/null || true
df -h /mnt/testfs | tail -1
sudo dmesg | grep -iE 'BUG|WARN|Call Trace' | tail -5 || echo "(dmesg clean)"
