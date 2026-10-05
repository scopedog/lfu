#!/bin/bash
# Where an offloaded lfs find's time goes.  $1 = server IP.
SRV=$1; M=/mnt/testfs; P="-mtime -30 -type f"
drop() { ssh -o BatchMode=yes $SRV 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null'
	 sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }
gcc -O2 -o /tmp/scanone ~/scanone.c -llustreapi || exit 1
TIMEFORMAT="wall %3R user %3U sys %3S"
one() {	# label cmd...
	local l=$1; shift
	for cache in cold warm; do
		[ $cache = cold ] && drop
		{ time sudo strace -f -T -e trace=ioctl -o /tmp/st "$@" >/tmp/out 2>/tmp/err; } 2>/tmp/tm
		local io=$(grep -o '<[0-9.]*>' /tmp/st | tr -d '<>' | awk '{s+=$1; n++} END {printf "%d ioctls %.3f s", n, s}')
		printf "%-22s %-4s %s  %s  lines %s\n" "$l" $cache "$(cat /tmp/tm)" "$io" "$(wc -l < /tmp/out)"
	done
}
for i in 1 2 3; do
	one "find --offload" lfs find $M --offload $P
	one "find nomatch" lfs find $M --offload $P -uid 4242
	one "raw 1 pass" /tmp/scanone $M
	one "raw 1 pass +link" /tmp/scanone $M link
done
# and without strace, the real wall
for i in 1 2 3; do drop; { time sudo lfs find $M --offload $P >/dev/null; } 2>&1 | sed 's/^/plain cold: /'; done
