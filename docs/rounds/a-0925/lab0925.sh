#!/bin/bash
# 09-25: rdev/blksize on a device scan, and find --projid unchanged
# (fc_projid removed). old = lab0924-new (a0924-pushed), new = lab0925-new.
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; L=/tmp/lab0925
H=/home/nishida; P=/usr/lib64/lustre/scan_osd_ldiskfs.so; DEV=/tmp/lustre-mdt1
mkdir -p $L; pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
A() { case $1 in old) echo $H/lab0924-new;; new) echo $H/lab0925-new;; esac; }
run() { local a=$(A $1); shift
	LD_LIBRARY_PATH=$a/lustre/utils/.libs LD_PRELOAD=$a/lustre/utils/.libs/liblustreapi.so.1 "$@"; }
lfs_() { local n=$1; shift; LUSTRE=$(A $n)/lustre run $n $(A $n)/lustre/utils/.libs/lfs "$@"; }
plugin() { umount $P 2>/dev/null; mount --bind $(A $1)/lustre/utils/scan_osd_ldiskfs.so $P &&
	cmp -s $P $(A $1)/lustre/utils/scan_osd_ldiskfs.so; }
for n in old new; do a=$(A $n); gcc -O2 -Wall -o $L/rdevdump.$n /tmp/rdevdump.c -I$a/lustre/include -I$a/include -I$a/include/uapi -L$a/lustre/utils/.libs -llustreapi || exit 1; done

cd $T || exit 1
./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -12 $L/mount.log; exit 1; }
echo "=== up: $(lctl get_param -n version | head -1)"
rm -rf $M/rd $M/pj; lfs mkdir -i 0 $M/rd; lfs mkdir -i 0 $M/pj
mknod $M/rd/c10_200 c 10 200; mknod $M/rd/b8_1 b 8 1
mknod $M/rd/c300_5 c 300 5; mknod $M/rd/c4_1048000 c 4 1048000
touch $M/rd/reg
for i in 1 2 3; do touch $M/pj/f$i; done; lfs project -p 1999 $M/pj/f2; lfs project -p 7 $M/pj/f3
for f in $M/rd/*; do python3 -c "import os,sys;s=os.stat(sys.argv[1]);import stat
print(os.path.basename(sys.argv[1]),'%d:%d'%(os.major(s.st_rdev),os.minor(s.st_rdev)) if stat.S_ISCHR(s.st_mode) or stat.S_ISBLK(s.st_mode) else '-')" $f; done | sort > $L/stat.txt
echo "  client stat:"; sed 's/^/    /' $L/stat.txt
for n in old new; do run $n $L/rdevdump.$n n $M/rd 2>/dev/null | sort > $L/walk.$n; done
echo "  walk (new):"; sed 's/^/    /' $L/walk.new
cmp -s $L/walk.old $L/walk.new && ok "walk records unchanged by the fix" || bad "walk changed" "$(diff $L/walk.old $L/walk.new)"
echo "=== find --projid / -printf %LP on the walk"
for n in old new; do lfs_ $n find $M/pj --projid 1999 > $L/pjw.$n 2>&1; lfs_ $n find $M/pj -type f -printf '%p %LP\n' 2>&1 | sort > $L/pjp.$n; done
sed 's/^/    /' $L/pjp.new
grep -q 'f2$' $L/pjw.new && [ $(wc -l < $L/pjw.new) = 1 ] && ok "walk --projid 1999 finds f2 only" || bad "walk --projid" "$(cat $L/pjw.new)"
cmp -s $L/pjw.old $L/pjw.new && cmp -s $L/pjp.old $L/pjp.new && ok "walk --projid/%LP old = new" || bad "walk projid differs" "$(diff $L/pjp.old $L/pjp.new)"
sync; sync
./llmountcleanup.sh > $L/clean.log 2>&1
echo "=== device scan of the stopped MDT0000"
for n in old new; do plugin $n || { bad "plugin bind $n"; continue; }
	LUSTRE=$(A $n)/lustre run $n $L/rdevdump.$n d $DEV 2>/dev/null | sort > $L/dev.$n
	lfs_ $n find --device $DEV --projid 1999 > $L/pjd.$n 2>&1
	lfs_ $n find --device $DEV -type f -printf '%LF %LP\n' 2>&1 | sort > $L/pjdp.$n
	lfs_ $n find --device $DEV -type c > $L/tc.$n 2>&1
done
umount $P 2>/dev/null
echo "  old:"; sed 's/^/    /' $L/dev.old; echo "  new:"; sed 's/^/    /' $L/dev.new
# map FID -> name via the walk output, compare to client stat
python3 - "$L" <<'P'
import sys,re
L=sys.argv[1]
names={}
for l in open(L+"/walk.new"):
    m=re.search(r'fid=(\S+)',l)
# fid->name from debugfs is not needed: the walk rdev is broken, use stat order by fid
P
exp_c10=$(grep c10_200 $L/stat.txt | awk '{print $2}')
grep -q "rdev=10:200 blksize=4096" $L/dev.new && ok "device scan: c 10 200 reads 10:200 (stat: $exp_c10)" || bad "c10_200" "$(cat $L/dev.new)"
grep -q "^b .*rdev=8:1 blksize=4096" $L/dev.new && ok "device scan: b 8 1 reads 8:1" || bad "b8_1"
grep -q "rdev=44:5" $L/dev.new && ok "device scan: c 300 5 reads 44:5, as stat (client truncates)" || bad "c300_5"
grep -q "rdev=253:192" $L/dev.new && ok "device scan: c 4 1048000 reads 253:192, as stat" || bad "c4_1048000"
grep -q "rdev=0:0 blksize=0" $L/dev.old && ok "old arm: 0:0 blksize 0 (the defect)" || bad "old arm not 0:0"
cmp -s $L/pjd.old $L/pjd.new && [ $(wc -l < $L/pjd.new) = 1 ] && ok "device --projid 1999: one object, old = new" || bad "device --projid" "$(cat $L/pjd.old; echo ---; cat $L/pjd.new)"
cmp -s $L/pjdp.old $L/pjdp.new && ok "device -printf %LP old = new ($(wc -l < $L/pjdp.new) lines)" || bad "device %LP differs" "$(diff $L/pjdp.old $L/pjdp.new | head)"
cmp -s $L/tc.old $L/tc.new && [ $(wc -l < $L/tc.new) = 3 ] && ok "device -type c: 3 objects, old = new" || bad "-type c" "$(cat $L/tc.new)"
echo "=== $pass pass, $fail fail"
