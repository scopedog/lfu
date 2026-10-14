#!/bin/bash
# 10-13 lab (as root on the clone VM): lreview items 2, 3 and 6 on ldiskfs.
# Usage: 08-items.sh <old arm> <new arm>
#  2: device scan, `! --foreign --mdt-count 2` on unstriped directories
#     old: prints them all (the stripe tests are skipped);  new: none
#  3: llapi_scan_rec_path() on a striped directory's shard
#     old: the master's pathname again;  new: -ENOENT (-2)
#  6: llapi_find_device() with the caller's lfsp_stats
#     old: left as the caller set it (zeros);  new: the scan's counters
set -u
O=/tmp/lab1013-it; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
M=/mnt/lfst
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
lfs mkdir -i 0 -c 1 $M/it || mkdir $M/it
mkdir $M/it/p1 $M/it/p2 $M/it/p3
lfs mkdir -i 0 -c 2 $M/it/sd || { echo "ABORT: no striped directory"; exit 5; }
touch $M/it/sd/f1 $M/it/sd/f2 $M/it/sd/f3 $M/it/sd/f4
echo "fixture: $(lfs getdirstripe -c $M/it/p1) stripes on p1, $(lfs getdirstripe -c $M/it/sd) on sd"
# unmount and mount again, so that everything is on the image and not in
# the journal; the scan below reads the image while it is mounted
bash ./llmountcleanup.sh > $O/cleanup1.txt 2>&1
env NOFORMAT=true bash ./llmount.sh > $O/llmount2.txt 2>&1
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount after the remount"; exit 4; }
[ -d $M/it/sd ] || { echo "ABORT: the remount reformatted"; exit 6; }
IMG=/tmp/lfst-mdt1
echo "image $IMG label $(e2label $IMG)"
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	for h in recpath fstats; do
		gcc -O2 -o /tmp/$h-$ARM /tmp/$h.c -D_GNU_SOURCE \
			-I$T/lustre/include -I$T/include -I$T/include/uapi \
			-L$P/lib -Wl,-rpath,$P/lib -llustreapi || echo "cc $h $ARM failed"
	done
	echo "== $ARM ($(cat /tmp/lab1009-$ARM.sha)) lib $(ldd /tmp/recpath-$ARM | grep -o "$P/lib/liblustreapi.so.1")"
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	i=0
	for pred in "-type d" "-type d --mdt-count 2" "-type d ! --mdt-count 2" \
		    "-type d ! --foreign" "-type d ! --foreign --mdt-count 2" \
		    "-type d ! --foreign ! --mdt-count 2" "-type d ! --foreign --mdt-hash crush"; do
		i=$((i+1))
		$LFS find --device $IMG $pred > $O/$ARM-2-$i.txt 2> $O/$ARM-2-$i.err
		echo "2 $ARM [$pred]: rc=$? lines=$(wc -l < $O/$ARM-2-$i.txt)"
	done
	unset LD_PRELOAD
	/tmp/recpath-$ARM $IMG $M > $O/$ARM-3.txt 2> $O/$ARM-3.err
	echo "3 $ARM $(cat $O/$ARM-3.err): $(grep -c . $O/$ARM-3.txt) directories; '$M/it/sd' named $(grep -c "^$M/it/sd\( \|$\)" $O/$ARM-3.txt) times; shard lines: $(grep 'shard' $O/$ARM-3.txt | tr '\n' ';')"
	/tmp/fstats-$ARM $IMG > $O/$ARM-6.txt 2> $O/$ARM-6.err
	echo "6 $ARM printed $(wc -l < $O/$ARM-6.txt) lines; $(tail -1 $O/$ARM-6.err)"
done
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo ITEMS DONE
