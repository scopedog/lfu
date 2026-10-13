#!/bin/bash
# 10-13 lab (as root on the clone VM): the two behaviour changes of the AI
# round on the 10-11 patchsets that a lab can show.  Usage: 01-round.sh <arm>...
#  C (68415): after a failed clear the scan stops clearing.  sc_user is not
#     registered, so every clear answers -ENOENT.
#     old: one "cannot clear" per 1000 records;  new: one.  Both return -2.
#  F (68159): `! --foreign` on a device scan no longer skips the other
#     predicates for an unstriped directory.
#     old: `! --foreign --uid 1000` prints every directory;  new: only 1000's.
set -u
exec > /tmp/lab1013-round.out 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > /tmp/lab1013-llmount.txt 2>&1
M=/mnt/lfst; MDT=lfst-MDT0000
mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
KEEP=$(lctl --device $MDT changelog_register -n -m CREAT)
mkdir $M/cp; ./createmany -o $M/cp/a 3500 > /dev/null
echo "--- C: log holds $(lfs changelog $MDT | wc -l) records, user $KEEP; sc_user=cl99 is not registered"
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM
	gcc -o /tmp/clear_point-$ARM /tmp/clear_point.c -D_GNU_SOURCE \
		-I$T/lustre/include -I$T/include -I$T/include/uapi \
		-L$P/lib -Wl,-rpath,$P/lib -llustreapi || { echo "cc $ARM failed"; continue; }
	/tmp/clear_point-$ARM $MDT cl99 > /tmp/lab1013-cp-$ARM.txt 2>&1
	echo "C $ARM ($(cat /tmp/lab1009-$ARM.sha)): $(grep RETURNED /tmp/lab1013-cp-$ARM.txt); 'cannot clear' x$(grep -c 'cannot clear' /tmp/lab1013-cp-$ARM.txt); lib $(ldd /tmp/clear_point-$ARM | grep -o "$P/lib/liblustreapi.so.1")"
done
# F fixture: five unstriped directories, two owned by uid 1000
mkdir $M/fd; mkdir $M/fd/r1 $M/fd/r2 $M/fd/r3 $M/fd/u1 $M/fd/u2
chown 1000 $M/fd/u1 $M/fd/u2
sync; sleep 2
bash ./llmountcleanup.sh > /tmp/lab1013-cleanup.txt 2>&1; echo "cleanup rc=$?"
MDTIMG=/tmp/lustre-mdt1
md5sum $MDTIMG > /tmp/lab1013-mdt.md5
echo "--- F: device scan of $MDTIMG (label $(e2label $MDTIMG))"
for ARM in "$@"; do
	T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
	export LD_PRELOAD=$P/lib/liblustreapi.so.1
	echo "F $ARM ($(cat /tmp/lab1009-$ARM.sha)) lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $LFS | grep lustreapi | tr -s ' \t' ' ')"
	i=0
	for pred in "-type d" "-type d --uid 1000" "-type d ! --foreign" \
		    "-type d ! --foreign --uid 1000" "-type d ! --foreign ! --uid 1000" \
		    "-type d ! --foreign --perm 0000" "-type d ! --foreign -name u1"; do
		i=$((i+1))
		$LFS find --device $MDTIMG $pred > /tmp/lab1013-f-$ARM-$i.txt 2> /tmp/lab1013-f-$ARM-$i.err
		echo "F $ARM [$pred]: rc=$? lines=$(wc -l < /tmp/lab1013-f-$ARM-$i.txt) md5=$(sort /tmp/lab1013-f-$ARM-$i.txt | md5sum | cut -c1-10) err=$(wc -l < /tmp/lab1013-f-$ARM-$i.err)"
	done
	unset LD_PRELOAD
done
md5sum -c --quiet /tmp/lab1013-mdt.md5 && echo "mdt image untouched"
echo "== end $(date '+%F %T')"
echo ROUND DONE
