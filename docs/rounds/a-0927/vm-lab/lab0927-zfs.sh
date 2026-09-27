#!/bin/bash
# 09-27: 68163 dc43e70c, a ZFS object's blocks include its dnode slots.
# Client `stat -c %b` of directories while zfst is mounted, then the pools
# exported and each arm's `lfs find --device <pool/mdt> --search` compared.
# Own fsname and vdev dir: the ldiskfs fixtures in /tmp are not touched.
set -u
H=/home/nishida; L=/tmp/lab0927-zfs; ZT=/tmp/zfslab27; M=/mnt/zfst
rm -rf $L; mkdir -p $L
exec > $L/run.txt 2>&1
lfs_() { local n=$1; shift; env LUSTRE=$H/lab0927z-$n/lustre LD_PRELOAD=$H/arm0927z$n/lib/liblustreapi.so.1 $H/lab0927z-$n/lustre/utils/.libs/lfs "$@"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
zpool list -H 2>/dev/null | grep . && { echo "ABORT: a pool is imported"; exit 2; }
md5sum /tmp/lfst-mdt1 /tmp/lfst-ost2 /tmp/lustre-mdt1 > $L/fixture.before
rm -rf $ZT; mkdir -p $ZT
cd /usr/lib64/lustre/tests
export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=$ZT LUSTRE=/usr/lib64/lustre
bash ./llmount.sh > $L/llmount.txt 2>&1
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no zfst client"; tail -20 $L/llmount.txt; exit 4; }
lctl get_param osd-zfs.*.mntdev
mkdir $M/zsmall $M/zmid $M/zbig
touch $M/zsmall/f
/usr/lib64/lustre/tests/createmany -o $M/zmid/f 300 > /dev/null
/usr/lib64/lustre/tests/createmany -o $M/zbig/f 3000 > /dev/null
sync; sleep 8; sync
for d in zsmall zmid zbig; do
	echo "$(lfs path2fid $M/$d) $(stat -c %b $M/$d) $d" >> $L/client
done
echo "client (fid, stat %b, dir):"; sed 's/^/  /' $L/client
MDTPOOL=$(lctl get_param -n osd-zfs.zfst-MDT0000.mntdev); echo "MDT dataset: $MDTPOOL"
bash ./llmountcleanup.sh > $L/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "pools imported after cleanup: [$(zpool list -H -o name 2>/dev/null | tr '\n' ' ')]"
ls -la $ZT
for n in new old; do
	echo "  $n lfs loads: $(LD_PRELOAD=$H/arm0927z$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 $H/lab0927z-$n/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')"
	env LUSTRE=$H/lab0927z-$n/lustre LD_PRELOAD=$H/arm0927z$n/lib/liblustreapi.so.1 strace -f -o $L/strace.$n -e trace=openat \
		$H/lab0927z-$n/lustre/utils/.libs/lfs find --device $MDTPOOL --search $ZT -type d -printf '%LF %b\n' > $L/dev.$n 2> $L/dev.$n.err
	echo "  $n rc=$? lines=$(wc -l < $L/dev.$n) err: $(head -3 $L/dev.$n.err | tr '\n' '|')"
	echo "  $n plugin: $(grep 'scan_osd_zfs' $L/strace.$n | grep -v ENOENT | head -1)"
done
pass=0; fail=0
while read f b d; do
	f=$(echo $f | tr -d '[]')
	bn=$(grep "^\[$f\] " $L/dev.new | awk '{print $2}'); bo=$(grep "^\[$f\] " $L/dev.old | awk '{print $2}')
	[ -z "$bn" ] && bn=$(grep "^$f " $L/dev.new | awk '{print $2}'); [ -z "$bo" ] && bo=$(grep "^$f " $L/dev.old | awk '{print $2}')
	echo "  $d: client=$b new=$bn old=$bo  new-old=$(( ${bn:-0} - ${bo:-0} ))"
	[ "$bn" = "$b" ] && pass=$((pass+1)) || fail=$((fail+1))
done < $L/client
echo "  new equals the client on $pass of 3 directories (mismatch $fail)"
echo "  all directories, new vs old:"; paste -d'|' <(sort $L/dev.new) <(sort $L/dev.old) | head -20 | sed 's/^/    /'
rm -rf $ZT
md5sum -c $L/fixture.before && echo "ldiskfs fixtures untouched"
echo "== end $(date '+%F %T')"
echo "ZFS RUN DONE"
