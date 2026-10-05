#!/bin/bash
# A/B: two-pass (installed) vs one-pass (build tree) offloaded lfs find.
SRV=$1; N=${N:-5}; M=/mnt/testfs; P="-mtime -30 -type f"
mkdir -p /tmp/A /tmp/B
cp /usr/bin/lfs /usr/lib64/liblustreapi.so.1.0.0 /tmp/A/
cp ~/lustre-release/lustre/utils/.libs/lfs ~/lustre-release/lustre/utils/.libs/liblustreapi.so.1.0.0 /tmp/B/
arm() { local a=$1; shift; sudo LD_PRELOAD=/tmp/$a/liblustreapi.so.1.0.0 /tmp/$a/lfs "$@"; }
drop() { ssh -o BatchMode=yes $SRV 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null'
	 sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }
echo "md5 A $(md5sum < /tmp/A/liblustreapi.so.1.0.0 | cut -c1-8)  B $(md5sum < /tmp/B/liblustreapi.so.1.0.0 | cut -c1-8)"
for a in A B; do
	n=$(sudo strace -f -e trace=ioctl -o /tmp/st.$a env LD_PRELOAD=/tmp/$a/liblustreapi.so.1.0.0 /tmp/$a/lfs find $M --offload $P -uid 4242 >/dev/null; grep -c ioctl /tmp/st.$a)
	echo "arm $a ioctls (nomatch, root): $n"
done
echo "== oracle: B vs walk, sorted"
bad=0
cmp1() { local w=$(arm B find "$@" --no-offload | sort | md5sum) o=$(arm B find "$@" --offload 2>/tmp/e | sort | md5sum) c=$(arm B find "$@" --offload 2>/dev/null | wc -l)
	 [ "$w" = "$o" ] && echo "SAME n=$c  $*" || { echo "DIFF  $*"; bad=1; }; }
cmp1 $M $P; cmp1 $M/bench $P; cmp1 $M/bench/d3 $P; cmp1 $M/d0 $P
cmp1 $M -type d -mtime -30; cmp1 $M/bench/ -type d -mtime -30
(cd $M/bench && cmp1 . -mtime -30 -name 'f12*')
[ $bad = 0 ] || { echo ORACLE FAILED; exit 1; }
TIMEFORMAT="%3R"
echo "== timed: scope arm cache wall"
for i in $(seq $N); do
	for s in "" bench/d3 d0; do
		for a in A B; do
			drop; t=$( { time arm $a find $M/$s --offload $P >/dev/null; } 2>&1 ); echo "/$s $a cold $t"
			t=$( { time arm $a find $M/$s --offload $P >/dev/null; } 2>&1 ); echo "/$s $a warm $t"
		done
	done
done
