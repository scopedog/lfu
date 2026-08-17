#!/bin/bash
# Stage 7 (ZFS): the filter matrix on a MOUNTED, SERVING ZFS MDT.
#
# The whole point of the run: before today every tier-1 line here would have
# been refused at start-up with "the kernel side cannot supply trusted.som ...".
DEV=lfufs-MDT0000-osd
cd ~/lfu
run() {
	sudo rmmod lfu_ring 2>/dev/null
	sudo insmod src/kernel/lfu_ring.ko dev=$DEV 2>/dev/null
	local label="$1"; shift
	local out rc
	out=$(sudo timeout 300 build/lfind-kmdt "$@" /dev/lfu_scan 2>&1); rc=$?
	# NOT a count of record lines: every run here passes -q, which prints
	# statistics and no records, so counting '[0x...' would report 0 for
	# everything.  The number wanted is the stats block's own emitted line.
	local n=$(echo "$out" | grep -oE '^emitted +: *[0-9]+' | grep -oE '[0-9]+$')
	local k=$(echo "$out" | grep -oE 'filtered \(t0\) *: *[0-9]+' | grep -oE '[0-9]+$')
	local k1=$(echo "$out" | grep -oE 'filtered \(t1\) *: *[0-9]+' | grep -oE '[0-9]+$')
	local u=$(echo "$out" | grep -oE 'undecided *: *[0-9]+' | grep -oE '[0-9]+$')
	local xa=$(echo "$out" | grep -oE 'xattr: inline=[0-9]+ external=[0-9]+ iget=[0-9]+')
	printf '%-40s rc=%-3s emitted=%-6s t0=%-6s t1=%-6s undec=%-4s %s\n' \
		"$label" "$rc" "$n" "${k:-.}" "${k1:-.}" "${u:-.}" "$xa"
}

echo "===== what the module says it can do on osd-zfs ====="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=$DEV
sudo build/lfind-kmdt -n 1 /dev/lfu_scan 2>&1 | head -8
echo "(the 'tier 1:' line above must list som lov lmv link -- it said 'none' before today)"
echo
echo "===== baseline ====="
run "(none)" -q
echo
echo "===== tier 0 ====="
run "--type f"          -q --type f
run "--type d"          -q --type d
run "--projid 1999"     -q --projid 1999
run "--uid 0"           -q --uid 0
run "--links +1"        -q --links +1
run "--attrs i"         -q --attrs i
run "--mtime -1d"       -q --mtime -1d
run "--dev-blocks +1G"  -q --dev-blocks +1G
echo
echo "===== tier 1 -- the new path, out of the SA xattr nvlist ====="
run "--blocks +1G  (SOM)"   -q --blocks +1G
run "--size +1G    (SOM)"   -q --size +1G
run "--size +1M    (SOM)"   -q --size +1M
run "--stripe-count 2"      -q --stripe-count 2
run "--stripe-count +1"     -q --stripe-count +1
run "--pool fast"           -q --pool fast
run "--ost 1"               -q --ost 1
run "--name 'named*'"       -q --name 'named*'
run "--name named2"         -q --name named2
run "--comp-count +1"       -q --comp-count +1
run "--mdt-count +1 (LMV)"   -q --mdt-count +1
run "--type f --blocks +1G" -q --type f --blocks +1G
run "-u --size +0"          -q -u --size +0
echo
echo "===== full stats line, tier 1 ====="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=$DEV
sudo timeout 300 build/lfind-kmdt -q --blocks +1G /dev/lfu_scan 2>&1 | tail -12
echo
echo "===== the object --blocks +1G found, in full ====="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=$DEV
sudo timeout 300 build/lfind-kmdt --blocks +1G /dev/lfu_scan 2>&1 | grep '^\[0x'
echo "client ground truth:"
stat -c 'size=%s' /mnt/lfufs/shapes/big1; lfs path2fid /mnt/lfufs/shapes/big1
echo
echo "--- dmesg ---"
sudo dmesg | grep -iE 'BUG|WARN|Call Trace|general protection|null pointer|slab' | tail -10 || echo "(clean)"
