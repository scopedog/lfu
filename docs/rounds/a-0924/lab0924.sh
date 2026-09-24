#!/bin/bash
# 09-24 AI round, old (pre-round) vs new arm, on a live 2-MDT ldiskfs fs.
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; L=/tmp/lab0924
H=/home/nishida; P=/usr/lib64/lustre/scan_osd_ldiskfs.so
mkdir -p $L; pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
A() { echo $H/lab0924-$1; }
run() { local a=$(A $1); shift
	LD_LIBRARY_PATH=$a/lustre/utils/.libs LD_PRELOAD=$a/lustre/utils/.libs/liblustreapi.so.1 "$@"; }
lfs_() { local n=$1; shift; LUSTRE=$(A $n)/lustre run $n $(A $n)/lustre/utils/.libs/lfs "$@"; }
plugin() { umount $P 2>/dev/null; mount --bind $(A $1)/lustre/utils/scan_osd_ldiskfs.so $P &&
	cmp -s $P $(A $1)/lustre/utils/scan_osd_ldiskfs.so; }

cd $T || exit 1
./llmountcleanup.sh > $L/clean0.log 2>&1 || true
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/mount.log 2>&1 || true
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; tail -12 $L/mount.log; exit 1; }
echo "=== up: $(lctl get_param -n version | head -1)"

echo "=== 1. llapi_scan_test (incl. test17's new cases), new arm"
rm -rf $M/lst; mkdir -p $M/lst
t=$(A new)/lustre/tests; b=$t/.libs/llapi_scan_test; [ -x $b ] || b=$t/llapi_scan_test
run new $b -d $M/lst -p /tmp > $L/lst.log 2>&1 && ok "llapi_scan_test ($(grep -c 'PASS\|passed' $L/lst.log) pass lines)" ||
	bad "llapi_scan_test" "$(grep -m3 -i 'fail\|assert' $L/lst.log)"

echo "=== 2. %Li / %Lo on Lustre directories"
rm -rf $M/pd; mkdir -p $M/pd/plain; lfs setdirstripe -c 2 $M/pd/striped
for n in old new; do lfs_ $n find $M/pd -type d -printf '%p [%Li] [%Lo]\n' 2>&1 | sort > $L/li.$n; done
sed 's/^/    /' $L/li.new
cmp -s $L/li.old $L/li.new && ok "%Li/%Lo unchanged on Lustre" || bad "%Li/%Lo changed" "$(diff $L/li.old $L/li.new)"

echo "=== 3. changelog: parent only on namespace records, prev 0, ss_emitted"
MDT=$(lctl dl | awk '/ mdt /{print $4; exit}' | sed 's/-MDT0000.*/-MDT0000/')
[ -n "$MDT" ] || MDT=lustre-MDT0000
lctl set_param -n mdd.$MDT.changelog_mask="+CLOSE" >/dev/null
CL=$(lctl --device $MDT changelog_register -n)
mkdir -p $M/cl; lfs setdirstripe -i 0 $M/cl/d0 2>/dev/null || mkdir -p $M/cl/d0
touch $M/cl/d0/f; echo x > $M/cl/d0/f; cat $M/cl/d0/f > /dev/null
mv $M/cl/d0/f $M/cl/d0/g; rm $M/cl/d0/g
for n in old new; do run $n $H/cldump.$n $MDT > $L/cl.$n 2>&1; done
echo "  new:"; sed 's/^/    /' $L/cl.new | head -20
c_old=$(grep -c "type=CLOSE  *parent=1" $L/cl.old); c_new=$(grep -c "type=CLOSE  *parent=1" $L/cl.new)
m_new=$(grep -c "type=MARK  *parent=1" $L/cl.new)
[ "$c_new" = 0 ] && [ "$m_new" = 0 ] && ok "no parent on CLOSE/MARK (new $c_new, old had $c_old)" ||
	bad "parent on CLOSE/MARK" "new CLOSE $c_new MARK $m_new"
grep "prev=" $L/cl.new | grep -vq "prev=0$" && bad "lfsr_event_prev not 0" || ok "lfsr_event_prev always 0"
echo "  stop: old [$(grep '^stop' $L/cl.old)] new [$(grep '^stop' $L/cl.new)]"
grep -q "^stop rc=-1 emitted=1" $L/cl.new && ok "a stopped scan counts the record it handed over" ||
	bad "ss_emitted on stop" "$(grep '^stop' $L/cl.new)"
t=$(A new)/lustre/tests; b=$t/.libs/llapi_scan_changelog_test; [ -x $b ] || b=$t/llapi_scan_changelog_test
rm -rf $M/llapi_scan_changelog_test.d; lfs mkdir -i 0 $M/llapi_scan_changelog_test.d
run new $b -m $MDT -d $M -u $CL > $L/clt.log 2>&1 && ok "llapi_scan_changelog_test" ||
	bad "llapi_scan_changelog_test" "$(grep -m3 -i 'fail\|assert' $L/clt.log)"
lctl --device $MDT changelog_deregister $CL >/dev/null 2>&1

echo "=== 4. --fid2path through a fileset mount"
mkdir -p $M/sub /mnt/sub; NID=$(lctl list_nids | head -1)
mount -t lustre $NID:/lustre/sub /mnt/sub || bad "fileset mount failed"
DEV=/tmp/lustre-mdt1
for n in old new; do lfs_ $n find --device $DEV --fid2path /mnt/sub -type f > $L/fs.$n 2>&1; echo "  $n: $(head -c 200 $L/fs.$n | tr '\n' '|')"; done
grep -q "subdirectory mount" $L/fs.new && ok "fileset mount refused" || bad "fileset mount not refused"
lfs_ new find --device $DEV --fid2path $M -type f > $L/fsw.new 2>&1
grep -q "subdirectory mount" $L/fsw.new && bad "whole-fs mount refused as fileset" || ok "whole-fs mount not taken for a fileset"
umount /mnt/sub

echo "=== 5. --paths over a --local sweep"
for n in old new; do lfs_ $n find --local --paths -type f > $L/sw.$n 2>&1; echo "  $n: $(grep -c 'OST' $L/sw.$n) OST lines: $(grep -m2 'OST' $L/sw.$n | tr '\n' '|' | cut -c1-160)"; done
[ "$(grep -c "failed for '.*OST" $L/sw.new)" = 0 ] && ok "no OST failures in a --paths sweep" || bad "OST failures remain"

echo "=== 9-prep: a striped directory on MDT0000"
rm -rf $M/sd; lfs mkdir -i 0 -c 2 $M/sd && createmany -o $M/sd/s 20 >/dev/null
sync; sync
echo "=== stopping for the device scans"
./llmountcleanup.sh > $L/clean.log 2>&1

echo "=== 6. device scan of the stopped MDT: blocks, sizes, %Li/%Lo"
for n in old new; do
	lfs_ $n find --device $DEV -printf '%LF %b %s [%Li] [%Lo]\n' 2>&1 | sort > $L/dev.$n; done
umount $P 2>/dev/null
echo "  $(wc -l < $L/dev.new) objects"
cmp -s $L/dev.old $L/dev.new && ok "device scan output identical" || bad "device scan changed" "$(diff $L/dev.old $L/dev.new | head -6)"

echo "=== 7. --maxdepth 0 over a target is refused"
lfs_ new find --device $DEV --maxdepth 0 -type f > $L/md.new 2>&1; rc=$?
[ $rc -ne 0 ] && grep -q "describes a walk" $L/md.new && ok "--maxdepth 0 refused (rc $rc)" || bad "--maxdepth 0 accepted" "$(head -2 $L/md.new)"

echo "=== 8. --paths names the root"
for n in old new; do lfs_ $n find --device $DEV --paths -type d > $L/root.$n 2>&1; done
echo "  old has /: $(grep -cx / $L/root.old)  new has /: $(grep -cx / $L/root.new)"
grep -qx / $L/root.new && ok "the root is printed as /" || bad "no / in --paths"

echo "=== 9. a striped directory: no shard in the path"
lfs_ new find --device $DEV --paths -type f > $L/sd.new 2>&1
ns=$(grep -c "^/sd/" $L/sd.new); bad_sd=$(grep "^/sd/" $L/sd.new | grep -vcE "^/sd/s[0-9]+$")
echo "  $ns files of /sd on MDT0000, $bad_sd with a shard"
[ $ns -gt 0 ] && [ $bad_sd -eq 0 ] && ok "striped dir paths" || bad "striped dir paths" "$(grep ^/sd/ $L/sd.new | head -3)"

echo "=== 10. the project quota inode"
PQ=$(dumpe2fs -h $DEV 2>/dev/null | awk -F: "/Project quota inode/{gsub(/ /,\"\",\$2); print \$2}")
for n in old new; do lfs_ $n find --device $DEV --internal -printf "%i\n" 2>/dev/null > $L/pq.$n; done
echo "  project quota inode $PQ: old $(grep -cx "$PQ" $L/pq.old), new $(grep -cx "$PQ" $L/pq.new)"
[ -n "$PQ" ] && [ "$(grep -cx "$PQ" $L/pq.new)" = 0 ] && ok "project quota inode not delivered" || bad "project quota inode" "PQ=$PQ"

echo "=== $pass passed, $fail failed"
