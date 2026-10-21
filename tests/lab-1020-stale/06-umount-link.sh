#!/bin/bash
# 10-20 round 2 (as root on the clone VM), stalefs fixture, after the
# lreview fixes.  Usage: 06-umount-link.sh <arm>... (old, ten2)
#   L: a file with ~4 KB of trusted.link (151 names); a remote scan of the
#      old arm stops at -E2BIG, the new one carries it as LFU_REC_LINK_BIG.
#   U (ten2 only; old LASSERTs by code): unmount the MDT while the ring is
#      full and the reader is not reading; unmount must finish, no LBUG,
#      and the reader end with ESHUTDOWN.
set -u
OUT=/tmp/stale-lab/r2; mkdir -p $OUT; exec >> $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') arms: $*"
for n in "$@"; do
	T=/tmp/stale-$n
	export LUSTRE=$T/lustre FSTYPE=ldiskfs MDSCOUNT=1 OSTCOUNT=1 TMP=/tmp/stalefs
	(cd $T/lustre/tests && NOFORMAT=1 bash llmount.sh) > $OUT/llmount.$n.txt 2>&1
	mount -t lustre | grep -q MDT0000 || { echo "ABORT $n mount"; exit 4; }
	k=$T/lustre/obdclass/obdclass.ko
	[ -f $k ] && [ "$(cat /sys/module/obdclass/srcversion 2>/dev/null)" = "$(modinfo -F srcversion $k)" ] || { echo "ABORT: loaded obdclass is not $n's"; exit 4; }
	insmod $T/lustre/lfu/lfu.ko ring_size=65536 batch=8192
	[ -f $T/lustre/lfu/lfu.ko ] && [ "$(cat /sys/module/lfu/srcversion 2>/dev/null)" = "$(modinfo -F srcversion $T/lustre/lfu/lfu.ko)" ] || { echo "ABORT lfu"; exit 4; }
	gcc -O2 -I$T/include/uapi -o $T/ringdump /tmp/ringdump.c
	gcc -O2 -I$T/lustre/include -I$T/include -I$T/include/uapi -include $T/config.h \
		-o $T/mountdump /tmp/mountdump.c -L$T/lustre/utils/.libs -llustreapi \
		-Wl,-rpath,$T/lustre/utils/.libs
	d=/mnt/lustre/blink.$n; mkdir $d; touch $d/f
	for i in $(seq 1 150); do ln $d/f $d/l$(printf %08d $i); done
	fid=$($T/lustre/utils/lfs path2fid $d/f); sync; sleep 3
	$T/mountdump /mnt/lustre > $OUT/L.$n.txt 2> $OUT/L.$n.err
	echo "L $n: mountdump rc=$? records=$(wc -l < $OUT/L.$n.txt) | $(tr '\n' ' ' < $OUT/L.$n.err)"
	echo "L $n: big-link file $fid -> $(awk -v f=$fid '$1 == f' $OUT/L.$n.txt | wc -l) record(s): $(awk -v f=$fid '$1 == f' $OUT/L.$n.txt | head -1)"
	echo "L $n: ring: $($T/ringdump lustre-MDT0000 2>/dev/null | awk -v f=${fid//[\[\]]/} '$1 == f' | wc -l) record(s) for it"
	if [ $n != old ]; then
		dmesg -C
		( $T/ringdump lustre-MDT0000 2> $OUT/U.$n.err | (sleep 20; cat > /dev/null) ) &
		sleep 3
		umount /mnt/lustre
		t0=$(date +%s.%N); umount /mnt/lustre-mds1; urc=$?; t1=$(date +%s.%N)
		echo "U $n: MDT umount rc=$urc in $(echo "$t1 - $t0" | bc) s"
		wait
		echo "U $n: reader: $(tr '\n' ' ' < $OUT/U.$n.err)"
		echo "U $n: dmesg LBUG/LASSERT: $(dmesg | grep -c 'LBUG\|ASSERTION')"
		grep -m3 'lfu\|ESHUTDOWN' <(dmesg) | head -3
	fi
	rmmod lfu
	(cd $T/lustre/tests && bash llmountcleanup.sh) > $OUT/cleanup.$n.txt 2>&1
	lsmod | grep -qE '^(lnet|obdclass) ' && { echo "ABORT modules left"; exit 4; }
done
echo "== end $(date '+%F %T')"
