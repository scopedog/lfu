#!/bin/bash
# 09-25: rdev on the ZFS backend.  old = lab0924-new + its own zfs plugin,
# new = lab0925-new + its own (the ABI differs: so_rdev is new).
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; L=/tmp/zlab0925
H=/home/nishida; P=/usr/lib64/lustre/scan_osd_zfs.so; MDT=lustre-mdt1/mdt1
mkdir -p $L; pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
A() { case $1 in old) echo $H/lab0924-new;; new) echo $H/lab0925-new;; esac; }
run() { local a=$(A $1); shift
	LD_LIBRARY_PATH=$a/lustre/utils/.libs LD_PRELOAD=$a/lustre/utils/.libs/liblustreapi.so.1 "$@"; }
lfs_() { local n=$1; shift; LUSTRE=$(A $n)/lustre run $n $(A $n)/lustre/utils/.libs/lfs "$@"; }
plugin() { umount $P 2>/dev/null; mount --bind $(A $1)/lustre/utils/scan_osd_zfs.so $P &&
	cmp -s $P $(A $1)/lustre/utils/scan_osd_zfs.so; }
for n in old new; do a=$(A $n); gcc -O2 -Wall -o $L/rdevdump.$n /tmp/rdevdump.c -I$a/lustre/include -I$a/include -I$a/include/uapi -L$a/lustre/utils/.libs -llustreapi || exit 1; done
cd $T || exit 1
./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -15 $L/mount.log; exit 1; }
echo "=== up (zfs): $(lctl get_param -n version | head -1)"
rm -rf $M/rd; lfs mkdir -i 0 $M/rd
mknod $M/rd/c10_200 c 10 200; mknod $M/rd/b8_1 b 8 1; mknod $M/rd/c4_1048000 c 4 1048000
for f in $M/rd/*; do python3 -c "import os,sys;s=os.stat(sys.argv[1]);print(os.path.basename(sys.argv[1]),'%d:%d'%(os.major(s.st_rdev),os.minor(s.st_rdev)))" $f; done | sort | sed 's/^/    /'
sync; ./llmountcleanup.sh > $L/clean.log 2>&1
for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p; done
echo "  pools imported: [$(zpool list -H -o name 2>/dev/null | tr '\n' ' ')]"
for n in old new; do plugin $n || { bad "plugin bind $n"; continue; }
	LUSTRE=$(A $n)/lustre run $n $L/rdevdump.$n d $MDT /tmp 2>$L/err.$n | sort > $L/dev.$n
	lfs_ $n find --device $MDT --search /tmp -type c > $L/tc.$n 2>&1
	lfs_ $n find --device $MDT --search /tmp -type f -printf '%LF %LP %s\n' 2>&1 | sort > $L/pf.$n
done
umount $P 2>/dev/null
echo "  old:"; sed 's/^/    /' $L/dev.old $L/err.old; echo "  new:"; sed 's/^/    /' $L/dev.new $L/err.new
grep -q "^c .*rdev=10:200 blksize=4096" $L/dev.new && ok "ZFS: c 10 200 reads 10:200" || bad "zfs c10_200"
grep -q "^b .*rdev=8:1 blksize=4096" $L/dev.new && ok "ZFS: b 8 1 reads 8:1" || bad "zfs b8_1"
grep -q "rdev=253:192" $L/dev.new && ok "ZFS: c 4 1048000 reads 253:192, as stat" || bad "zfs c4"
grep -q "rdev=0:0" $L/dev.old && ok "ZFS old arm: 0:0 (the defect)" || bad "zfs old not 0:0"
cmp -s $L/tc.old $L/tc.new && [ $(wc -l < $L/tc.new) = 2 ] && ok "ZFS -type c: 2, old = new" || bad "zfs -type c" "$(cat $L/tc.old; echo --; cat $L/tc.new)"
cmp -s $L/pf.old $L/pf.new && ok "ZFS -type f -printf %LF %LP %s: old = new ($(wc -l < $L/pf.new))" || bad "zfs printf differs" "$(diff $L/pf.old $L/pf.new | head)"
echo "=== $pass pass, $fail fail"
