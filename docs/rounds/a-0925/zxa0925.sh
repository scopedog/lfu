#!/bin/bash
# 09-25: do osd-zfs xattr objects (xattr dir, spilled values) reach a
# device scan, and as what?  Run as root on the clone VM.
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; L=/tmp/zxa0925
H=/home/nishida; P=/usr/lib64/lustre/scan_osd_zfs.so; MDT=lustre-mdt1/mdt1
A=${ARM:-$H/lab0925-new}
mkdir -p $L
gcc -O2 -Wall -o $L/statdump /tmp/statdump.c -I$A/lustre/include -I$A/include -I$A/include/uapi -L$A/lustre/utils/.libs -llustreapi || exit 1
run() { LD_LIBRARY_PATH=$A/lustre/utils/.libs LD_PRELOAD=$A/lustre/utils/.libs/liblustreapi.so.1 "$@"; }
scan() {	# $1 = label; fs must be stopped and pools exported
	umount $P 2>/dev/null; mount --bind $A/lustre/utils/scan_osd_zfs.so $P
	LUSTRE=$A/lustre run $L/statdump $MDT /tmp > $L/st.$1 2>&1
	umount $P 2>/dev/null
	echo "== $1"; sed 's/^/   /' $L/st.$1
}
stop() { sync; cd $T; ./llmountcleanup.sh > $L/clean.$1.log 2>&1
	for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p; done; }
start() { cd $T; NOFORMAT=1 MDSCOUNT=1 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/mount.$1.log 2>&1
	mount -t lustre | grep -q "on $M " || { echo NOMOUNT $1; tail -15 $L/mount.$1.log; exit 1; }; }
cd $T || exit 1
./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=1 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -15 $L/mount.log; exit 1; }
echo "=== up (zfs): $(lctl get_param -n version | head -1)"
mkdir $M/x; for i in 1 2 3; do touch $M/x/plain$i; done
stop base; scan base; start mid
# 1: a user xattr too big for the SA -> xattr dir + one value object
for i in 1 2 3; do touch $M/x/big$i
	setfattr -n user.big -v 0s$(head -c 40000 /dev/urandom | base64 -w0) $M/x/big$i || echo SETFATTR_FAIL; done
# 1b: two of them on one file: the second cannot fit the 64 KB SA
for i in 1 2; do touch $M/x/two$i
	for n in a b; do setfattr -n user.big$n -v 0s$(head -c 40000 /dev/urandom | base64 -w0) $M/x/two$i || echo SETFATTR_FAIL; done; done
getfattr -d $M/x/two1 2>/dev/null | grep -c '^user' | sed 's/^/   two1 user xattrs: /'
# 2: a PFL layout wide enough that trusted.lov spills
lfs setstripe $(for s in $(seq 1 60); do echo -n "-E ${s}M -c 1 "; done) -E -1 -c 1 $M/x/pfl1 2>&1 | tail -1
getfattr -n trusted.lov --only-values $M/x/pfl1 2>/dev/null | wc -c | sed 's/^/   pfl1 trusted.lov bytes: /'
getfattr -d $M/x/big1 | head -c 60; echo
stop after; scan after
zdb -dddd $MDT 2>/dev/null | grep -cE "ZFS directory|ZFS plain file" | sed "s/^/   zdb dir+file objects: /"
