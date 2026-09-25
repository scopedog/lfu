#!/bin/bash
# 09-25: A/B of the ZFS backend's xattr-object filter on ONE fixture.
# old/new = /tmp/scan_osd_zfs.{old,new}.so built from r0925b-tip and the fix.
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; L=/tmp/zxab0925
H=/home/nishida; P=/usr/lib64/lustre/scan_osd_zfs.so; MDT=lustre-mdt1/mdt1
A=$H/lab0925-new; mkdir -p $L; pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
gcc -O2 -Wall -o $L/statdump /tmp/statdump.c -I$A/lustre/include -I$A/include -I$A/include/uapi -L$A/lustre/utils/.libs -llustreapi || exit 1
run() { LUSTRE=$L/arm-$ARM LD_LIBRARY_PATH=$A/lustre/utils/.libs LD_PRELOAD=$A/lustre/utils/.libs/liblustreapi.so.1 "$@"; }
# liblustreapi dlopens $LUSTRE/utils/scan_osd_zfs.so (PLUGIN_DIR is absent)
plugin() { mkdir -p $L/arm-$1/utils; cp /tmp/scan_osd_zfs.$1.so $L/arm-$1/utils/scan_osd_zfs.so; ARM=$1; }
cd $T || exit 1
./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=1 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -15 $L/mount.log; exit 1; }
echo "=== up (zfs): $(lctl get_param -n version | head -1)"
mkdir $M/x; for i in 1 2 3; do touch $M/x/plain$i; done
for i in 1 2; do touch $M/x/two$i
	for n in a b; do setfattr -n user.big$n -v 0s$(head -c 40000 /dev/urandom | base64 -w0) $M/x/two$i; done; done
touch $M/x/three; for n in a b c; do setfattr -n user.big$n -v 0s$(head -c 40000 /dev/urandom | base64 -w0) $M/x/three; done
lfs setstripe $(for s in $(seq 1 60); do echo -n "-E ${s}M -c 1 "; done) -E -1 -c 1 $M/x/pfl1
mknod $M/x/c1 c 10 200
echo "  expected xattr objects: two1,two2 = dir+1 value each, three = dir+2 values -> 7"
sync; ./llmountcleanup.sh > $L/clean.log 2>&1
for p in $(zpool list -H -o name 2>/dev/null); do zpool export $p; done
for r in 1 2; do for n in old new; do plugin $n || { bad "bind $n"; continue; }
	run $L/statdump $MDT /tmp > $L/st.$n.$r 2>&1
	run $A/lustre/utils/.libs/lfs find --device $MDT --search /tmp -printf '%LF %m %u %s %LP\n' 2>&1 | sort > $L/pf.$n.$r
done; done
for n in old new; do echo "  $n:"; sed 's/^/    /' $L/st.$n.1; done
cmp -s $L/st.old.1 $L/st.old.2 && cmp -s $L/st.new.1 $L/st.new.2 && ok "each arm repeats itself" || bad "arm not stable"
g() { sed -n "s/.*$2=\([0-9]*\).*/\1/p" $L/st.$1.1 | head -1; }
c() { sed -n "s/^class\[$2\]=//p" $L/st.$1.1; }
[ "$(g old skipped)" = 7 ] && ok "old: the 7 xattr objects are counted as skipped" || bad "old skipped=$(g old skipped)"
[ "$(g new skipped)" = 0 ] && ok "new: skipped 0" || bad "new skipped=$(g new skipped)"
[ $(( $(g old seen) - $(g new seen) )) = 7 ] && ok "new sees exactly 7 fewer" || bad "seen old=$(g old seen) new=$(g new seen)"
same=1; for i in 0 1 2 3 4 5 6; do [ "$(c old $i)" = "$(c new $i)" ] || same=0; done
[ $same = 1 ] && ok "every class count identical (NO_LMA $(c new 4))" || bad "classes differ"
[ "$(g old emitted)" = "$(g new emitted)" ] && [ "$(g old nofid)" = "$(g new nofid)" ] && ok "--internal: emitted and no-FID records identical" || bad "emitted/nofid differ"
grep -v '^lfs find:' $L/pf.old.1 > $L/pr.old; grep -v '^lfs find:' $L/pf.new.1 > $L/pr.new
cmp -s $L/pr.old $L/pr.new && ok "lfs find --device -printf records: old = new ($(wc -l < $L/pr.new))" || bad "records differ" "$(diff $L/pr.old $L/pr.new | head)"
grep -q 'objects were skipped' $L/pf.old.1 && ! grep -q 'skipped' $L/pf.new.1 && ok "the false 'skipped: unreadable or inconsistent' warning is gone" || bad "warning" "$(grep skipped $L/pf.*.1)"
echo "=== $pass pass, $fail fail"
