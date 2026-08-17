#!/bin/bash
# Their filtered rates, measured by WALL TIME over the objects the walk visits,
# not by the count it emits -- a filter that emits nothing is not a scan at
# infinity.  Their walk visits the whole namespace either way.
set -u
MDT=testfs-MDT0000
SCANNED=302012          # what their unfiltered walk reports on this namespace

wall() {   # wall <label> <args...>
	local label="$1"; shift
	local rs=""
	for p in 1 2 3; do
		local t0=$(date +%s.%N)
		sudo timeout 900 lctl iterate_objects "$@" $MDT > /dev/null 2>&1
		local t1=$(date +%s.%N)
		rs="$rs $(python3 -c "print(int($SCANNED/max($t1-$t0,1e-9)))")"
	done
	local med=$(echo $rs | tr ' ' '\n' | sort -n | sed -n 2p)
	printf '    %-38s %-9s (%s)\n' "$label" "$med" "$rs"
}
echo "=== THEIRS: objects VISITED per second, medians of three ==="
printf '    %-38s %-9s\n' "configuration" "obj/s"
wall "no filter, no --print-*"
wall "--print-size (their shipped default use)"      --print-size
wall "--uid 4242            (rejects all)"           --uid 4242
wall "--size +1G            (rejects all)"           --size +1G
wall "--mtime +365d         (rejects all)"           --mtime +365d
wall "--size -1M            (matches all)"           --size -1M
