#!/bin/bash
# Stage 7: the filter matrix, evaluated in the kernel.
# Each run reloads the module: SET_FILTER is refused once the scan has begun,
# and one reader at a time.
cd ~/lfu
run() {                 # run <label> <args...>
	sudo rmmod lfu_ring 2>/dev/null
	sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd 2>/dev/null
	local label="$1"; shift
	local out rc
	out=$(sudo timeout 180 build/lfind-kmdt "$@" /dev/lfu_scan 2>&1)
	rc=$?
	local n=$(echo "$out" | grep -c '^\[0x')
	local k=$(echo "$out" | grep -oE 'filtered \(t0\) *: *[0-9]+' | grep -oE '[0-9]+$')
	local k1=$(echo "$out" | grep -oE 'filtered \(t1\) *: *[0-9]+' | grep -oE '[0-9]+$')
	local u=$(echo "$out" | grep -oE 'undecided *: *[0-9]+' | grep -oE '[0-9]+$')
	local xa=$(echo "$out" | grep -oE 'xattr: inline=[0-9]+ external=[0-9]+ iget=[0-9]+')
	printf '%-42s rc=%-3s emitted=%-6s t0=%-6s t1=%-6s undec=%-4s %s\n' \
		"$label" "$rc" "$n" "${k:-.}" "${k1:-.}" "${u:-.}" "$xa"
	echo "$out" > /tmp/last-$$.txt
}

echo "===== no filter (baseline) ====="
run "(none)" -q
echo
echo "===== tier 0, evaluated in kernel ====="
run "--type f"                    -q --type f
run "--type d"                    -q --type d
run "--projid 1999"               -q --projid 1999
run "--uid 0"                     -q --uid 0
run "--links +1"                  -q --links +1
run "--attrs i"                   -q --attrs i
run "! --type f"                  -q '!' --type f
run "--mtime -1d"                 -q --mtime -1d
run "--btime -1d"                 -q --btime -1d
run "--dev-blocks +1G"            -q --dev-blocks +1G
echo
echo "===== tier 1: rec(DORA_XATTR) out of the mapped block ====="
run "--blocks +1G  (SOM)"         -q --blocks +1G
run "--size +1G    (SOM)"         -q --size +1G
run "--size +1M    (SOM)"         -q --size +1M
run "--stripe-count 4"            -q --stripe-count 4
run "--stripe-count +4"           -q --stripe-count +4
run "--pool fast"                 -q --pool fast
run "--ost 3"                     -q --ost 3
run "--layout mdt   (DoM)"        -q --layout mdt
run "--name 'report*'"            -q --name 'report*'
run "--name second_link.txt"      -q --name second_link.txt
run "--comp-count +1"             -q --comp-count +1
echo
echo "===== combined, the LUG slide-21 shape ====="
run "--type f --mtime -1d --blocks +1G" -q --type f --mtime -1d --blocks +1G
run "-u --size +0 (undecided?)"   -q -u --size +0
echo
echo "===== a full stats line ====="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
sudo timeout 180 build/lfind-kmdt -q --blocks +1G /dev/lfu_scan 2>&1 | tail -12
echo
echo "--- dmesg: anything alarming? ---"
sudo dmesg | grep -iE 'BUG|WARN|Call Trace|general protection|null pointer' | tail -10 || echo "(clean)"
