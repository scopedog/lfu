#!/bin/bash
# 68020's filter, on an MDT and on an OST.
set -u
MDT=testfs-MDT0000
OST=testfs-OST0000
BIG='0x200000401:0x7:0x0'      # big1, 1.5 GiB, 4 stripes
LC="sudo timeout 600 lctl"

echo "=== 1. what size does their MDT walk report for the 1.5 GiB striped file? ==="
$LC iterate_objects --print-size --print-time $MDT 2>/dev/null | grep -F "$BIG" | sed 's/^/    /'
echo "    (the client says 1610612736; trusted.som says 1610612736)"

echo
echo "=== 2. the shapes, as their walk sees them ==="
for f in 0x5 0x7 0x9 0xb; do
	$LC iterate_objects --print-size $MDT 2>/dev/null | grep -F "0x200000401:$f:0x0" | sed 's/^/    /'
done

echo
echo "=== 3. their size filter on the MDT ==="
for expr in +1G +100M +1M -1M -1k 0; do
	n=$($LC iterate_objects --size "$expr" $MDT 2>/dev/null | grep -c '^\[')
	printf '    --size %-6s -> %8s objects\n' "$expr" "$n"
done

echo
echo "=== 4. their size filter on an OST, where the data actually is ==="
for expr in +1G +100M +1M; do
	n=$($LC iterate_objects --size "$expr" $OST 2>/dev/null | grep -c '^\[')
	printf '    --size %-6s -> %8s objects\n' "$expr" "$n"
done
echo "    largest few OST objects:"
$LC iterate_objects --print-size $OST 2>/dev/null | sort -t= -k2 -n | tail -3 | sed 's/^/      /'

echo
echo "=== 5. does filtering save them scan work? (MDT, medians of three) ==="
timeit() {   # timeit <label> <args...>
	local label="$1"; shift
	local best=""
	for p in 1 2 3; do
		local t0=$(date +%s.%N)
		local n=$(sudo timeout 900 lctl iterate_objects "$@" $MDT 2>/dev/null | grep -c '^\[')
		local t1=$(date +%s.%N)
		local r=$(python3 -c "print(int($n/max($t1-$t0,1e-9)))")
		best="$best $r"
	done
	local med=$(echo $best | tr ' ' '\n' | sort -n | sed -n 2p)
	printf '    %-34s objects=%-8s rate=%-9s (%s)\n' "$label" "$n" "$med" "$best"
}
timeit "no filter"
timeit "--uid 4242 (rejects everything)"   --uid 4242
timeit "--size +1G (rejects everything)"   --size +1G
timeit "--mtime +365d (rejects all)"       --mtime +365d
