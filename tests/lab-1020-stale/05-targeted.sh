#!/bin/bash
# 10-20, targeted reuse (as root on the clone VM), both arms on the stalefs
# fixture.  The scan sleeps 4 s on file x's inode, after next() took its
# FID and attributes; meanwhile x is unlinked, the cache purged and files
# created until one takes x's inode.  old should emit x's FID with the new
# file's name; new should drop it and count ls_stale.
set -u
OUT=/tmp/stale-lab/tgt; mkdir -p $OUT; exec > $OUT/run.txt 2>&1
for n in old new; do
	T=/tmp/stale-$n
	export LUSTRE=$T/lustre FSTYPE=ldiskfs MDSCOUNT=1 OSTCOUNT=1 TMP=/tmp/stalefs
	(cd $T/lustre/tests && NOFORMAT=1 bash llmount.sh) > $OUT/llmount.$n.txt 2>&1
	insmod $T/lustre/lfu/lfu.ko
	[ "$(cat /sys/module/lfu/srcversion)" = "$(modinfo -F srcversion $T/lustre/lfu/lfu.ko)" ] || { echo "ABORT lfu"; exit 4; }
	gcc -O2 -I$T/include/uapi -o $T/ringdump /tmp/ringdump.c
	d=/mnt/lustre/tgt.$n; mkdir $d; touch $d/x; sync; sleep 2
	read xfid xino <<< $($T/ringdump lustre-MDT0000 2>/dev/null | awk '$3 == "x" {print $1, $5}' | tail -1)
	echo "$n: x is $xfid ino $xino"
	echo $xino > /sys/module/lfu/parameters/lab_delay_ino
	echo 4000000 > /sys/module/lfu/parameters/lab_delay_us
	$T/ringdump lustre-MDT0000 > $OUT/$n.scan 2> $OUT/$n.stats &
	sleep 0.5
	rm $d/x
	for r in $(seq 1 10); do
		sync; echo 2 > /proc/sys/vm/drop_caches
		for i in $(seq 1 30); do touch $d/y$r.$i; done
	done
	wait
	echo 0 > /sys/module/lfu/parameters/lab_delay_us
	echo 0 > /sys/module/lfu/parameters/lab_delay_ino
	now=$($T/ringdump lustre-MDT0000 2>/dev/null | awk -v i=$xino '$5 == i {print $1, $3}')
	echo "$n: ino $xino now holds: ${now:-nothing}"
	echo "$n: in the delayed scan, records with ino $xino: $(awk -v i=$xino '$5 == i {print $1, $3}' $OUT/$n.scan | tr '\n' ' ')"
	echo "$n: records with x's FID: $(grep -c "^$xfid " $OUT/$n.scan) | $(cat $OUT/$n.stats)"
	rmmod lfu; (cd $T/lustre/tests && bash llmountcleanup.sh) > $OUT/cleanup.$n.txt 2>&1
done
echo "== end"
