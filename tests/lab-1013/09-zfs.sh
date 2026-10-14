#!/bin/bash
# 10-13 lab (as root on the clone VM): lreview items 4 and 5, the ZFS backend.
# Usage: [RACE_DELAYS="..." RACE_REPS=n] 09-zfs.sh <old arm> <new arm>
#  5: libzpool brought up twice in one process.  `lfs find --device ... --mdt 0`
#     opens the target twice.
#     old: "crypto_register_provider() failed" on stderr;  new: none
#  4: two threads open a dataset and its snapshot in one exported pool, the
#     second a few ms after the first.
#     old: one of them can answer -ENOENT (-2);  new: both 0
set -u
O=/tmp/lab1013-zfs; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=2 TMP=/tmp/zfslab1013 LUSTRE=/usr/lib64/lustre
rm -rf $TMP; mkdir -p $TMP
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/zfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; tail -5 $O/llmount.txt; exit 4; }
mkdir $M/z; ./createmany -o $M/z/f 2000 > /dev/null; sync; sleep 3
DS=$(zfs list -H -o name | grep -m1 'mdt1/')
[ -n "$DS" ] || { echo "ABORT: no MDT dataset"; zfs list; exit 5; }
POOL=${DS%%/*}
zfs snapshot $DS@s1 || { echo "ABORT: snapshot failed"; exit 5; }
bash ./llmountcleanup.sh > $O/cleanup1.txt 2>&1
zpool list -H -o name 2>/dev/null | grep -qx $POOL && zpool export $POOL
zpool list -H -o name 2>/dev/null | grep -qx $POOL && { echo "ABORT: $POOL still imported"; exit 6; }
echo "dataset $DS, snapshot $DS@s1, vdevs in $TMP: $(ls $TMP | tr '\n' ' ')"
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	gcc -O2 -pthread -o /tmp/zrace-$ARM /tmp/zrace.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || echo "cc zrace $ARM failed"
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) lib $(ldd /tmp/zrace-$ARM | grep -o "$P/lib/liblustreapi.so.1"); plugin $(ls -l $P/lib/lustre/scan_osd_zfs.so | awk '{print $5}') bytes"
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	i=0
	for opt in "" "--mdt 0" "-type f --mdt 0"; do
		i=$((i+1)); t0=$(date +%s.%N)
		timeout 300 $LFS find --device $DS --search $TMP $opt > $O/$ARM-5-$i.txt 2> $O/$ARM-5-$i.err
		rc=$?
		echo "5 $ARM [$opt]: rc=$rc lines=$(wc -l < $O/$ARM-5-$i.txt) md5=$(sort $O/$ARM-5-$i.txt | md5sum | cut -c1-10) warnings=$(grep -c crypto_register_provider $O/$ARM-5-$i.err) stderr-lines=$(wc -l < $O/$ARM-5-$i.err) secs=$(echo "$(date +%s.%N) - $t0" | bc | cut -c1-5)"
	done
	unset LD_PRELOAD
	bad=0; runs=0
	for d in ${RACE_DELAYS:-0 5 10 15 20 25 30 40 60}; do
		for k in $(seq 1 ${RACE_REPS:-3}); do
			r=$(timeout 300 /tmp/zrace-$ARM $DS $DS@s1 $TMP $d 2>/dev/null)
			runs=$((runs+1))
			echo "$d ms: $r" >> $O/$ARM-4.txt
			echo "$r" | grep -q "rc=0 .*rc=0 " || bad=$((bad+1))
		done
	done
	echo "4 $ARM: $runs runs, $bad with a failed open; return values seen: $(grep -o 'rc=-\?[0-9]*' $O/$ARM-4.txt | sort | uniq -c | tr '\n' ' ')"
	grep -v "rc=0 .*rc=0 " $O/$ARM-4.txt | head -5
done
zpool list -H -o name 2>/dev/null | grep -qx $POOL && echo "NOTE: $POOL is imported in the kernel now"
rm -rf $TMP
echo "== end $(date '+%F %T')"
echo ZFS DONE
