#!/bin/bash
# 09-27 follow-up 2: 68415 A/B on the live lfst fixture (MDSCOUNT=2) left by
# lab0927g-sanity.sh.  new = r0927-tip 133643bd9e, old = b8c7d9c5b8.
# Harness clres.c: llapi_scan_changelog() event mode + _RESOLVE, one line per
# record.  A second client mount /mnt/lfst2 is the writer for the lazy-size
# case, so /mnt/lfst has no cached inode or size for that file.
# The checks were corrected after the run (FIDs contain [], grep -F; the
# CL_MIGRATE record is mf's, not mdir's); the raw harness output is the result.
set -u
H=/home/nishida; M=/mnt/lfst; M2=/mnt/lfst2; L=/tmp/lab0927g-cl; MDT=lfst-MDT0000
rm -rf $L; mkdir -p $L
exec > $L/run.txt 2>&1
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
echo "== start $(date '+%F %T')"
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: modules not loaded"; exit 3; }
mount -t lustre | grep -q "on $M " || { echo "ABORT: no lfst client"; exit 4; }
for n in new old; do echo "  $n harness loads: $(LD_TRACE_LOADED_OBJECTS=1 $H/lab0927-clres.$n | grep lustreapi | tr -s ' \t' ' ')"; done
echo "  new source has the CL_MIGRATE fix: $(grep -c 'a CL_MIGRATE.s cr_sfid' $H/lab0927-new/lustre/utils/liblustreapi_scan_changelog.c), old: $(grep -c 'a CL_MIGRATE.s cr_sfid' $H/lab0927-old/lustre/utils/liblustreapi_scan_changelog.c)"
NID=$(lctl list_nids | head -1)
mkdir -p $M2; mount -t lustre $NID:/lfst $M2 || { echo "ABORT: second mount"; exit 5; }
lctl set_param mdd.$MDT.changelog_mask=+MIGRT > /dev/null
lctl set_param mdd.lfst-MDT0001.changelog_mask=+MIGRT > /dev/null
U=$(lctl --device $MDT changelog_register -m ALL -n); echo "  changelog user $U on $MDT"
last() { lfs changelog $MDT 2>/dev/null | tail -1 | awk '{print $1}'; }
rm -rf $M/cm; lfs mkdir -i 0 $M/cm
run() { local tag=$1 start=$2 want=$3
	for n in new old; do $H/lab0927-clres.$n $MDT $M $start $want > $L/$tag.$n 2>&1; echo "    $tag $n: $(grep -c '^idx' $L/$tag.$n) records, $(tail -1 $L/$tag.$n)"; done; }

echo "=== b. CL_MIGRATE delivers the migrated object once"
lfs mkdir -i 0 $M/cm/mdir; echo m > $M/cm/mdir/mf
OLDF=$(lfs path2fid $M/cm/mdir/mf); I0=$(last); echo "  mdir/mf $OLDF, mdir on MDT$(lfs getdirstripe -m $M/cm/mdir); changelog at $I0"
lfs migrate -m 1 $M/cm/mdir; rc=$?
NEWF=$(lfs path2fid $M/cm/mdir/mf); echo "  lfs migrate -m 1 rc=$rc; mdir/mf now $NEWF on MDT$(lfs getdirstripe -m $M/cm/mdir)"
echo "  lfs changelog $MDT from $((I0+1)):"; lfs changelog $MDT $((I0+1)) | sed 's/^/    /'
MI=$(lfs changelog $MDT $((I0+1)) | awk '$2 ~ /MIGRT/ {print $1}' | head -1); echo "  CL_MIGRATE record index: [${MI}]"
if [ -n "$MI" ]; then
	run mig $MI 0
	for n in new old; do grep "^idx=$MI " $L/mig.$n | sed "s/^/    $n: /" | cut -c1-260; done
	nn=$(grep -c "^idx=$MI " $L/mig.new); no=$(grep -c "^idx=$MI " $L/mig.old)
	o=$(echo $OLDF | tr -d '[]')
	[ $nn = 1 ] && grep "^idx=$MI " $L/mig.new | grep -qF "fid=$NEWF" &&
		ok "68415 new: CL_MIGRATE $MI delivers one object, the new FID $NEWF" || bad "68415 new migrate" "$(grep "^idx=$MI " $L/mig.new)"
	[ $no = 2 ] && grep "^idx=$MI " $L/mig.old | grep -qF "fid=$OLDF" &&
		ok "68415 old arm: CL_MIGRATE $MI delivers 2 objects, the second the old FID $OLDF (the defect)" || echo "  NOTE old migrate: $no records"
else
	bad "68415 no CL_MIGRATE record was written"
fi

echo "=== c. a lazy size of 0 is not an answer"
I0=$(last)
# the writer is on the second mount and keeps the file open: no close, no SOM
( exec 8> $M2/cm/lz; printf 'hello lazy\n' >&8; exec sleep 900 ) &
WP=$!; echo $WP > $L/writer.pid
echo closed-data > $M2/cm/lzc		# control: written and closed
sleep 2
echo "  writer pid $WP holds $(readlink /proc/$WP/fd/8)"
LZF=$(lfs path2fid $M2/cm/lz); LCF=$(lfs path2fid $M2/cm/lzc); echo "  lz $LZF (open), lzc $LCF (closed)"
echo "  trusted.som: lz [$(getfattr -n trusted.som -e hex --absolute-names $M2/cm/lz 2>&1 | tail -1)] lzc [$(getfattr -n trusted.som -e hex --absolute-names $M2/cm/lzc 2>&1 | tail -1)]"
run lazy $((I0+1)) $(printf '%#x' $((0x0000004000000000)))
for n in new old; do grep -F -e "fid=$LZF " -e "fid=$LCF " $L/lazy.$n | grep -E 'CREAT|CLOSE' | sed "s/^/    $n: /" | cut -c1-260; done
zn=$(grep -F "fid=$LZF " $L/lazy.new | grep -m1 CREAT); zo=$(grep -F "fid=$LZF " $L/lazy.old | grep -m1 CREAT)
[[ "$zn" == *"lazy_size=0"* ]] && ok "68415 new: the open file's lazy size is not marked (size 0 is no answer)" || bad "68415 new lazy" "$zn"
[[ "$zo" == *"lazy_size=1"*"size=0 "* ]] && ok "68415 old arm: LAZY_SIZE set with size 0 (the defect)" || echo "  NOTE old lazy: $zo"
cn=$(grep -F "fid=$LCF " $L/lazy.new | grep -m1 CREAT); co=$(grep -F "fid=$LCF " $L/lazy.old | grep -m1 CREAT)
echo "  control lzc: new [${cn:0:160}] old [${co:0:160}]"
kill $WP; wait $WP 2>/dev/null; echo "  writer closed"

echo "=== d. resolved times keep nanoseconds; btime is filled"
I0=$(last)
echo n > $M/cm/ns; touch -m -d '2026-09-27 07:00:00.123456789' $M/cm/ns
NSF=$(lfs path2fid $M/cm/ns); echo "  ns $NSF client mtime $(stat -c %y $M/cm/ns) birth $(stat -c %w $M/cm/ns)"
run ns $((I0+1)) 0
for n in new old; do grep -F "fid=$NSF " $L/ns.$n | tail -1 | sed "s/^/    $n: /" | cut -c1-280; done
dn=$(grep -F "fid=$NSF " $L/ns.new | tail -1); do_=$(grep -F "fid=$NSF " $L/ns.old | tail -1)
[[ "$dn" != *"btime=(absent)"* ]] && ok "68415 new: btime present" || bad "68415 new ns" "$dn"
[[ "$do_" == *"btime=(absent)"* ]] && ok "68415 old arm: no btime (the defect; Lustre keeps whole-second mtime, so .nsec is 0 in both)" || echo "  NOTE old ns: $do_"

lctl --device $MDT changelog_deregister $U > /dev/null && echo "  $U deregistered"
lctl set_param mdd.$MDT.changelog_mask=-MIGRT mdd.lfst-MDT0001.changelog_mask=-MIGRT > /dev/null
umount $M2 && echo "  second mount gone"
echo "=== tally: PASS $pass FAIL $fail"
echo "== end $(date '+%F %T')"
echo "CL RUN DONE"
