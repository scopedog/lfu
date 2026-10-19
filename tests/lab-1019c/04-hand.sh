#!/bin/bash
# 10-19 lab c (root): %LF / %LO by hand on arm t, against lfs path2fid and
# lfs getstripe -y.  FSNAME=lfsh, one MDT, two OSTs, installed framework.
set -u
T=/tmp/lab1019c-t; L=$T/lustre/utils/.libs/lfs; OUT=/tmp/lab1019c-hand
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') arm t ($(cat /tmp/lab1019c-t.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfsh MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
M=/mnt/lfsh; D=$M/h
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no client"; exit 4; }
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 $L | grep lustreapi | tr -s ' \t' ' ')"
mkdir $D
$L setstripe -c 1 -i 0 $D/f0; echo a > $D/f0
$L setstripe -c 1 -i 1 $D/f1; echo b > $D/f1
$L setstripe -c 2 $D/s2; dd if=/dev/zero of=$D/s2 bs=1M count=2 status=none
$L setstripe -E 1M -c 1 -i 0 -E -1 -c 2 $D/pfl
dd if=/dev/zero of=$D/pfl bs=1M count=3 status=none
$L setstripe -E 1M -c 1 -i 1 -E -1 -c 2 $D/pfl1  # second component never written
echo c > $D/pfl1
$L setstripe -c 1 -i 0 $D/nowrite                 # an object with no data
mkdir $D/dir
echo "--- truth: path2fid and getstripe -y l_ost_idx/l_fid"
for f in f0 f1 s2 pfl pfl1 nowrite; do
	fid=$($L path2fid $D/$f | tr -d '[]')
	echo "$f $fid $($L getstripe -y $D/$f | awk '/l_ost_idx:/ {i=$NF} /l_fid:/ {printf "ost%s=%s ", i, $2}')"
	$L getstripe -y $D/$f | awk -v f=$f -v fid=$fid '/l_ost_idx:/ {i=$NF} /l_fid:/ {print f, fid, i, $2}' >> $OUT/truth.txt
done
echo "--- client walk -printf '%p %LF %LO'"
$L find $D -printf '%p %LF %LO\n' | tee $OUT/walk.txt
sync; sync
MDT=$(mount -t lustre | awk '$3 ~ /lfsh-mdt1/ {print $1}')
OST1=$(mount -t lustre | awk '$3 ~ /lfsh-ost1/ {print $1}')
OST2=$(mount -t lustre | awk '$3 ~ /lfsh-ost2/ {print $1}')
echo "devices: mdt=$MDT ost1=$OST1 ost2=$OST2"
umount $M
for m in $(mount -t lustre | awk '{print $3}' | sort -r); do umount $m; done
mount -t lustre | awk '{print "still mounted: "$3}'
echo "--- MDT scan, --type f -printf '%LF %LO'"
$L find --device $MDT --type f -printf '%LF %LO\n' | sort | tee $OUT/mdt.txt
for o in OST1:$OST1 OST2:$OST2; do
	echo "--- ${o%%:*} scan -printf '%LF %LO'"
	$L find --device ${o#*:} -printf '%LF %LO\n' | sort | tee $OUT/${o%%:*}.txt
	echo "    (default output, first 3: $($L find --device ${o#*:} | head -3 | tr '\n' ' '))"
done
echo "--- checks"
ok=0; bad=0
while read -r p fid lo; do
	[[ $p == $D/dir || $p == $D ]] && continue
	grep -qxF "$fid $lo" $OUT/mdt.txt && ok=$((ok+1)) || { bad=$((bad+1)); echo "MDT MISS $p $fid $lo"; }
done < $OUT/walk.txt
echo "MDT: $ok files match the walk, $bad do not"
ok=0; bad=0
while read -r f fid idx ofid; do
	if grep -qxF "$fid [$ofid]" $OUT/OST$((idx + 1)).txt; then
		ok=$((ok+1))
	else
		bad=$((bad+1))
		echo "OST$((idx + 1)) $f: want '$fid [$ofid]', have '$(grep -F "[$ofid]" $OUT/OST$((idx + 1)).txt)'"
	fi
done < $OUT/truth.txt
echo "OST: $ok objects give file FID + own FID, $bad do not"
echo "== end $(date '+%F %T')"
env FSNAME=lfsh timeout 300 bash ./llmountcleanup.sh > $OUT/clean.txt 2>&1
echo "HAND DONE"
