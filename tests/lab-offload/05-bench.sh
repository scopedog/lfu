#!/bin/bash
# lfs find, one binary, two arms: --no-offload (the namespace walk, one RPC
# per object) and --offload (llapi_scan_mount(), the MDT streams its objects).
# $1 = server IP.  Runs on the client.  Caches dropped on BOTH nodes before
# every timed run; arms alternate; median of N.
SRV=$1; N=${N:-5}; M=/mnt/testfs
OUT=~/bench; mkdir -p $OUT
P="-mtime -30 -type f"
drop() { ssh -o BatchMode=yes $SRV 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null'
	 sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }

echo "== version: $(sudo lctl get_param -n version) srv: $(ssh $SRV sudo lctl get_param -n version)"

echo "== oracle: sorted pathnames, walk vs offload"
fail=0
for s in "" bench bench/d3 d0; do
	sudo lfs find $M/$s --no-offload $P | sort > $OUT/w.txt
	sudo lfs find $M/$s --offload $P 2>$OUT/o.err | sort > $OUT/o.txt
	d=$(diff $OUT/w.txt $OUT/o.txt | grep -c '^[<>]')
	printf "%-10s walk %6d  offload %6d  diff %d  stderr: %s\n" "/$s" \
		$(wc -l < $OUT/w.txt) $(wc -l < $OUT/o.txt) $d "$(head -c 200 $OUT/o.err)"
	[ $d = 0 ] || { fail=1; diff $OUT/w.txt $OUT/o.txt | head -5; }
done
# the automatic choice: root, a predicate the MDT answers alike
sudo lfs find $M -uid 0 -type f --no-offload | sort > $OUT/w.txt
sudo strace -f -e trace=ioctl -o $OUT/auto.strace lfs find $M -uid 0 -type f | sort > $OUT/o.txt
printf "%-10s walk %6d  auto   %6d  diff %d  ioctls %s (a walk makes one per file)\n" "auto /" \
	$(wc -l < $OUT/w.txt) $(wc -l < $OUT/o.txt) \
	$(diff $OUT/w.txt $OUT/o.txt | grep -c '^[<>]') \
	$(grep -c "ioctl(" $OUT/auto.strace)
[ $fail = 0 ] || { echo "ORACLE FAILED"; exit 1; }

run() {	# scope arm extra-args...
	local s=$1 arm=$2; shift 2
	drop
	local t0=$(date +%s.%N)
	local c=$(sudo lfs find $M/$s "$@" 2>/dev/null | wc -l)
	local t1=$(date +%s.%N)
	local w=$(awk -v a=$t0 -v b=$t1 'BEGIN { printf "%.3f", b - a }')
	# a wall of 0 is a broken clock, not a fast run
	awk -v w=$w 'BEGIN { exit !(w > 0) }' || { echo "BAD WALL $w" >&2; exit 1; }
	printf "%s %s %s %s\n" "/$s" $arm $c $w
}
echo "== timed: scope arm count wall"
for i in $(seq $N); do
	for s in "" bench bench/d3 d0; do
		run "$s" walk --no-offload $P
		run "$s" offload --offload $P
	done
	run "" auto-walk -uid 0 -type f --no-offload
	run "" auto -uid 0 -type f
done | tee $OUT/raw.txt
[ ${PIPESTATUS[0]} = 0 ] || { echo "TIMED RUN FAILED"; exit 1; }
echo "STAGE5 OK"
