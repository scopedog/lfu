#!/bin/bash
# 09-27 arms: new = r0927-tip 73d04cd04d (lab0927-new), old = r0926b-tip b8c7d9c5b8 (lab0927-old).
# Phase A runs on the live lfst fixture left by lab0927-sanity.sh; phase B
# tears it down and works on disposable COPIES of the quiescent images.
set -u
H=/home/nishida; M=/mnt/lfst; L=/tmp/lab0927-arms
rm -rf $L; mkdir -p $L
exec > $L/run.txt 2>&1
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
T() { echo $H/lab0927-$1; }
lfs_() { local n=$1; shift; env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0927$n/lib/liblustreapi.so.1 $(T $n)/lustre/utils/.libs/lfs "$@"; }
# run an lfs command in both arms: rc, stderr and stdout kept per arm
both() { local tag=$1; shift
	[ -e $L/$tag.new.rc ] && { echo "TAG CLASH: $tag"; exit 9; }
	for n in new old; do
		lfs_ $n "$@" > $L/$tag.$n.out 2> $L/$tag.$n.err; echo $? > $L/$tag.$n.rc
		echo "  [$tag] $n rc=$(cat $L/$tag.$n.rc) out=$(wc -l < $L/$tag.$n.out) err: $(head -3 $L/$tag.$n.err | tr '\n' '|' | cut -c1-230)"
	done; }
rc() { cat $L/$1.$2.rc; }
nl_() { wc -l < $L/$1.$2.out; }
echo "== start $(date '+%F %T')"
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: modules not loaded"; exit 3; }
mount -t lustre | grep -q "on $M " || { echo "ABORT: no lfst client"; exit 4; }
[ -e /dev/lfu_scan ] && echo "NOTE: /dev/lfu_scan present" || echo "no /dev/lfu_scan: mounted targets are read by the device backend"
lctl get_param osd-*.*.mntdev
MDTDEV=$(lctl get_param -n osd-*.lfst-MDT0000.mntdev); OSTDEV=$(lctl get_param -n osd-*.lfst-OST0000.mntdev)
echo "MDTDEV=$MDTDEV OSTDEV=$OSTDEV"
for n in new old; do
	echo "  $n lfs loads: $(LD_PRELOAD=$H/arm0927$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 $(T $n)/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')"
	echo "  $n plugin: $(env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0927$n/lib/liblustreapi.so.1 strace -f -e trace=openat $(T $n)/lustre/utils/.libs/lfs find --device $MDTDEV -type d 2>&1 >/dev/null | grep 'scan_osd_' | grep -v ENOENT | head -2 | tr '\n' ' ')"
	echo "  $n lfs has \"join its directories with ':'\": $(strings $(T $n)/lustre/utils/.libs/lfs | grep -c "join its directories with")"
done

echo "=== fixture on lfst"
rm -rf $M/lab27; lfs mkdir -i 0 $M/lab27
for i in 1 2 3 4 5; do lfs setstripe -i 1 -c 1 $M/lab27/o1f$i; dd if=/dev/zero of=$M/lab27/o1f$i bs=64k count=1 status=none; done
for g in g1 g2; do lfs setstripe -i 0 -c 1 $M/lab27/$g; dd if=/dev/zero of=$M/lab27/$g bs=1M count=2 status=none; done
lfs getstripe -i $M/lab27/o1f1 $M/lab27/g1 | tr '\n' ' '; echo
sync; sleep 1

echo "=== 68160: the glimpse probe on a start path"
for n in new old; do
	lctl set_param -n ldlm.namespaces.*osc*.lru_size=clear > /dev/null
	e0=$(lctl get_param -n ost.OSS.ost.stats | awk '$1=="ldlm_enqueue"{print $2}')
	env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0927$n/lib/liblustreapi.so.1 strace -f -o $L/gl.$n.strace -e trace=%stat \
		$(T $n)/lustre/utils/.libs/lfs find --lazy $M/lab27/g1 $M/lab27/g2 --size +1G > $L/gl.$n.out 2> $L/gl.$n.err
	echo $? > $L/gl.$n.rc
	e1=$(lctl get_param -n ost.OSS.ost.stats | awk '$1=="ldlm_enqueue"{print $2}')
	echo "  $n rc=$(cat $L/gl.$n.rc) out=$(wc -l < $L/gl.$n.out); OST ldlm_enqueue ${e0:-0} -> ${e1:-0}"
	for g in g1 g2; do echo "    $n first call on $g: $(grep -m1 "lab27/$g\"" $L/gl.$n.strace | cut -d' ' -f2- | cut -c1-200)"; done
done
grep -m1 'lab27/g1"' $L/gl.new.strace | grep -q 'statx(AT_FDCWD, "/mnt/lfst/lab27/g1", AT_STATX_DONT_SYNC, STATX_TYPE,' &&
	ok "68160 new: the start path is probed with statx(AT_STATX_DONT_SYNC, STATX_TYPE)" || bad "68160 new probe" "$(grep -m1 'lab27/g1"' $L/gl.new.strace)"
grep -m1 'lab27/g1"' $L/gl.old.strace | grep -qE 'newfstatat|^[0-9]+ +stat\(' &&
	ok "68160 old arm: a full stat() of the start path (the defect)" || echo "  NOTE old first call: $(grep -m1 'lab27/g1"' $L/gl.old.strace)"
both bare find $MDTDEV --type f
both bared find --device $MDTDEV --type f
[ "$(rc bare new)" = 0 ] && [ $(nl_ bare new) -gt 0 ] && cmp -s $L/bare.new.out $L/bared.new.out &&
	ok "68160 new: a bare block device path is still a device scan ($(nl_ bare new) files, = --device)" || bad "68160 bare device" "$(head -3 $L/bare.new.err)"

echo "=== 68159: a failed probe says it once"
both dup1 find --device /nonexistent/dev --pool foo
both dup2 find --device /nonexistent/dev --stripe-count 1
both dup3 find --device /nonexistent/dev -type f
for t in dup1 dup2 dup3; do for n in new old; do echo "  --- $t $n stderr:"; sed 's/^/      /' $L/$t.$n.err; done; done
[ $(grep -c . $L/dup1.new.err) = 1 ] && [ $(grep -c . $L/dup2.new.err) = 1 ] && [ "$(rc dup1 new)" != 0 ] &&
	ok "68159 new: --pool / --stripe-count on a bad device: one error line, rc $(rc dup1 new)" || bad "68159 new dup error" "$(cat $L/dup1.new.err)"
[ $(grep -c . $L/dup1.old.err) -gt 1 ] && ok "68159 old arm: $(grep -c . $L/dup1.old.err) lines for --pool (the defect)" || echo "  NOTE old dup1: $(grep -c . $L/dup1.old.err) lines"
cmp -s $L/dup3.new.err $L/dup3.old.err && ok "68159 control (-type f, no layout option): new = old stderr" || echo "  NOTE dup3 stderr differs"

echo "=== 68288: an orphan in PENDING is not given its old path"
rm -rf $M/dorph; lfs mkdir -i 0 $M/dorph
echo data > $M/dorph/f; echo keep > $M/dorph/keep
F=$(lfs path2fid $M/dorph/f); echo "  dorph/f is $F"
( exec 7< $M/dorph/f; exec sleep 900 ) &
SP=$!; echo $SP > $L/sleeper.pid; sleep 1
ls -l /proc/$SP/fd/7
rm $M/dorph/f; sync; sleep 6; sync; sync
echo "  PENDING on $MDTDEV:"; debugfs -c -R 'ls -l /PENDING' $MDTDEV 2>/dev/null | sed 's/^/    /'
if debugfs -c -R 'ls /PENDING' $MDTDEV 2>/dev/null | grep -q '0x'; then
	both orphall find --device $MDTDEV --internal --paths
	both orphname find --device $MDTDEV --internal --paths --name f
	both orphfid find --device $MDTDEV --internal --name f
	both orphvis find --device $MDTDEV --paths --name f
	for t in orphall orphname orphfid orphvis; do for n in new old; do
		echo "    $t $n: $(grep -E 'dorph|0x' $L/$t.$n.out | sort | tr '\n' ' ' | cut -c1-300)  stderr: $(grep -v '^#' $L/$t.$n.err | tr '\n' '|' | cut -c1-200)"; done; done
	! grep -qx /dorph/f $L/orphall.new.out && ! grep -qx /dorph/f $L/orphname.new.out && grep -qx /dorph/keep $L/orphall.new.out &&
		ok "68288 new: no /dorph/f for the orphan; /dorph/keep still named" || bad "68288 new orphan" "$(grep dorph $L/orphall.new.out $L/orphname.new.out)"
	grep -qx /dorph/f $L/orphall.old.out && ok "68288 old arm: printed /dorph/f for the PENDING orphan (the defect)" || echo "  NOTE old arm did not print /dorph/f"
	grep -q "$(echo $F | tr -d '[]')" $L/orphfid.new.out && ok "68288 new: the orphan's record is still delivered ($F without --paths)" || echo "  NOTE orphan FID not in orphfid.new.out"
else
	echo "  NOTE: no orphan reached PENDING on the device; arm not run"
fi
kill $SP; wait $SP 2>/dev/null; echo "  sleeper closed"

echo "=== 68288 df006952: a remote hardlink as linkea entry 0 (DNE)"
rm -rf $M/dh0 $M/dh1; lfs mkdir -i 0 $M/dh0; lfs mkdir -i 1 $M/dh1
echo "  dh0 on MDT$(lfs getdirstripe -m $M/dh0), dh1 on MDT$(lfs getdirstripe -m $M/dh1)"
echo h > $M/dh0/f; ln $M/dh0/f $M/dh1/g && mv $M/dh0/f $M/dh0/f2
HF=$(lfs path2fid $M/dh0/f2); echo "  dh0/f2 is $HF, links $(stat -c %h $M/dh0/f2), on MDT$(lfs getstripe -m $M/dh0/f2)"
echo "  lfs fid2path, in linkea order: $(lfs fid2path $M $HF | tr '\n' ' ')"
sync; sleep 6; sync; sync
echo "  trusted.link of /ROOT/dh0/f2 on $MDTDEV (debugfs -c):"
debugfs -c -R 'ea_get /ROOT/dh0/f2 trusted.link' $MDTDEV 2>/dev/null | sed 's/^/    /'
both dh find --device $MDTDEV --paths --type f
both dhf2 find --device $MDTDEV --paths --type f --name f2
both dhg find --device $MDTDEV --paths --type f --name g
for t in dh dhf2 dhg; do for n in new old; do
	echo "    $t $n: $(grep -E '/dh[01]/' $L/$t.$n.out | sort | tr '\n' ' ')  stderr: $(grep -v '^#' $L/$t.$n.err | tr '\n' '|' | cut -c1-200)"; done; done
grep -qx /dh0/f2 $L/dh.new.out && grep -qx /dh0/f2 $L/dhf2.new.out &&
	ok "68288 new: the file is named /dh0/f2 through linkea entry 1" || bad "68288 new remote hardlink" "$(grep dh $L/dh.new.out $L/dhf2.new.out)"
! grep -q '/dh0/f2' $L/dh.old.out && ok "68288 old arm: no path for the file whose entry 0 is remote (the defect)" || echo "  NOTE old arm printed: $(grep dh $L/dh.old.out)"

echo "=== teardown"
cd /usr/lib64/lustre/tests
env FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre timeout 300 bash ./llmountcleanup.sh > $L/cleanup.txt 2>&1; echo "  cleanup rc=$?"
mount -t lustre | awk '{print "  LEFT MOUNTED: " $3}'
for m in $(dmsetup ls | grep flakey | cut -f1); do dmsetup remove $m; done
for d in $(losetup -a | grep -E '/tmp/lfst-|lab0927' | cut -d: -f1); do losetup -d $d; done
md5sum /tmp/lfst-mdt1 /tmp/lfst-ost2 > $L/fixture.before

echo "=== 68159: --ost/--mdt against a relabelled COPY"
OC=/tmp/lab0927-ost.img; cp --sparse=always /tmp/lfst-ost2 $OC
echo "  copy of lfst-ost2, label [$(e2label $OC)]"
for lab in lfst-OST0001 'lfst=OST0001' 'lfst:OST0001' 'lfst+OST0001'; do
	tune2fs -L "$lab" $OC > /dev/null; s=$(echo "$lab" | tr '=:+-' 'ecpd')
	echo "  label now [$(e2label $OC)]"
	both op$s find --device $OC --ost lfst-OST0001_UUID
	both on$s find --device $OC ! --ost lfst-OST0001_UUID
	both oi$s find --device $OC --ost 1
done
for s in lfstdOST0001 lfsteOST0001 lfstcOST0001 lfstpOST0001; do
	echo "  $s: +uuid new=$(nl_ op$s new) old=$(nl_ op$s old) | !uuid new=$(nl_ on$s new) old=$(nl_ on$s old) | index new=$(nl_ oi$s new) old=$(nl_ oi$s old)"
done
N=$(nl_ oilfstdOST0001 new); echo "  objects on the OST copy (control, --ost 1): $N"
[ "$N" -gt 0 ] || bad "68159 control: the OST copy has no objects"
for s in lfsteOST0001 lfstcOST0001 lfstpOST0001; do
	[ $(nl_ op$s new) = $N ] && [ $(nl_ on$s new) = 0 ] && [ $(nl_ oi$s new) = $N ] &&
		ok "68159 new, label $s: --ost UUID $N, ! --ost 0, --ost 1 $N" || bad "68159 new label $s" "+$(nl_ op$s new) !$(nl_ on$s new) i$(nl_ oi$s new)"
	[ $(nl_ op$s old) = 0 ] && [ $(nl_ on$s old) = $N ] && ok "68159 old arm, label $s: --ost UUID 0, ! --ost $N (the defect)" || echo "  NOTE old $s: +$(nl_ op$s old) !$(nl_ on$s old)"
done
[ $(nl_ oplfstdOST0001 new) = $N ] && [ $(nl_ oplfstdOST0001 old) = $N ] && ok "68159 control: label lfst-OST0001 matches in both arms" || bad "68159 control label"
MC=/tmp/lab0927-mdt.img; cp --sparse=always /tmp/lfst-mdt1 $MC
echo "  copy of lfst-mdt1, label [$(e2label $MC)]"
for lab in lfst-MDT0000 'lfst=MDT0000' 'lfst:MDT0000'; do
	tune2fs -L "$lab" $MC > /dev/null; s=$(echo "$lab" | tr '=:+-' 'ecpd')
	echo "  label now [$(e2label $MC)]"
	both mp$s find --device $MC --mdt lfst-MDT0000_UUID -type f
	both mn$s find --device $MC ! --mdt lfst-MDT0000_UUID -type f
	both mi$s find --device $MC --mdt 0 -type f
done
N=$(nl_ milfstdMDT0000 new); echo "  files on the MDT copy (control, --mdt 0): $N"
for s in lfsteMDT0000 lfstcMDT0000; do
	echo "  $s: +uuid new=$(nl_ mp$s new) old=$(nl_ mp$s old) | !uuid new=$(nl_ mn$s new) old=$(nl_ mn$s old) | index new=$(nl_ mi$s new) old=$(nl_ mi$s old)"
	[ $(nl_ mp$s new) = $N ] && [ $(nl_ mn$s new) = 0 ] && [ "$N" -gt 0 ] && ok "68159 new, MDT label $s: --mdt UUID $N, ! --mdt 0" || bad "68159 new MDT label $s" "+$(nl_ mp$s new) !$(nl_ mn$s new)"
	[ $(nl_ mp$s old) = 0 ] && ok "68159 old arm, MDT label $s: --mdt UUID 0 (the defect)" || echo "  NOTE old MDT $s: +$(nl_ mp$s old) !$(nl_ mn$s old)"
done
echo "=== 68160: a bare loop device of the MDT copy"
tune2fs -L lfst-MDT0000 $MC > /dev/null; LP=$(losetup -f --show -r $MC)
both loopbare find $LP --type f
both loopdev find --device $MC --type f
[ "$(rc loopbare new)" = 0 ] && [ $(nl_ loopbare new) -gt 0 ] && cmp -s $L/loopbare.new.out $L/loopdev.new.out &&
	ok "68160 new: bare loop device $LP scanned, $(nl_ loopbare new) files = --device on the image" || bad "68160 bare loop" "$(head -3 $L/loopbare.new.err)"
losetup -d $LP; rm -f $OC $MC
md5sum -c $L/fixture.before && echo "  fixture images untouched"

echo "=== tally: PASS $pass FAIL $fail"
echo "== end $(date '+%F %T')"
echo "ARMS RUN DONE"
