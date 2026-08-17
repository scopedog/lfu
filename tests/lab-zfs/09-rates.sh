#!/bin/bash
# Stage 9 (ZFS): rates, warm, one enumerator.  Three medians of three: no
# filter, a rejecting tier-0 filter, and a tier-1 filter that reads an xattr
# for every object.  On ldiskfs those came out 3.59M / 3.88M / 2.63M.
DEV=lfufs-MDT0000-osd
cd ~/lfu
rate() {
	local label="$1"; shift
	local best=() r
	for i in 1 2 3; do
		sudo rmmod lfu_ring 2>/dev/null
		sudo insmod src/kernel/lfu_ring.ko dev=$DEV 2>/dev/null
		# the line is "rate            : 263890 objects/sec"; an earlier
		# version grepped "objects scanned/sec" and silently got 0 for
		# every row, which looks exactly like a scanner that did nothing
		r=$(sudo timeout 600 build/lfind-kmdt -q "$@" /dev/lfu_scan 2>&1 |
		    grep -oE '^rate +: *[0-9]+' | grep -oE '[0-9]+$')
		best+=("${r:-0}")
	done
	printf '%-32s %s\n' "$label" "$(printf '%s\n' "${best[@]}" | sort -n | sed -n 2p) (runs: ${best[*]})"
}
echo "=== warm, single enumerator ==="
rate "no filter"
rate "--uid 4242 (tier 0, rejects all)" --uid 4242
rate "--type f (tier 0, matches all)"   --type f
rate "--blocks +1G (tier 1, SOM)"       --blocks +1G
rate "--name 'zzz*' (tier 1, linkea)"   --name 'zzz*'
