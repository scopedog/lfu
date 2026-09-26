#!/bin/bash
# 09-26 arms: new = r0926b-tip (lab0926-new), old = r0925c-tip (lab0926-old).
# Runs on the live lfst fixture left by lab0926-sanity.sh, adds a second
# filesystem "lustre" (own loop files, lfst's MGS), then tears both down and
# runs the device-file checks on the quiescent lfst MDT image.
set -u
H=/home/nishida; M=/mnt/lfst; L=/tmp/lab0926-arms; LB=$H/lab0926
rm -rf $L; mkdir -p $L
exec > $L/run.txt 2>&1
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
T() { echo $H/lab0926-$1; }
lfs_() { local n=$1; shift; env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0926$n/lib/liblustreapi.so.1 $(T $n)/lustre/utils/.libs/lfs "$@"; }
# run an lfs command in both arms: rc, stderr and stdout kept per arm
both() { local tag=$1; shift
	for n in new old; do
		lfs_ $n "$@" > $L/$tag.$n.out 2> $L/$tag.$n.err; echo $? > $L/$tag.$n.rc
		echo "  [$tag] $n rc=$(cat $L/$tag.$n.rc) out=$(wc -l < $L/$tag.$n.out) err: $(head -3 $L/$tag.$n.err | tr '\n' '|' | cut -c1-230)"
	done; }
rc() { cat $L/$1.$2.rc; }
echo "== start $(date '+%F %T')"
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: modules not loaded"; exit 3; }
mount -t lustre | grep -q "on $M " || { echo "ABORT: no lfst client"; exit 4; }
[ -e /dev/lfu_scan ] && echo "NOTE: /dev/lfu_scan present" || echo "no /dev/lfu_scan: mounted targets are read by the device backend"
lctl get_param osd-*.*.mntdev
MDTDEV=$(lctl get_param -n osd-*.lfst-MDT0000.mntdev); OSTDEV=$(lctl get_param -n osd-*.lfst-OST0000.mntdev)
OSTMNT=$(mount | awk -v d=$OSTDEV '$1==d{print $3}')
echo "MDTDEV=$MDTDEV OSTDEV=$OSTDEV OSTMNT=$OSTMNT"
for n in new old; do
	echo "  $n lfs loads: $(LD_PRELOAD=$H/arm0926$n/lib/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 $(T $n)/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')"
	echo "  $n plugin: $(env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0926$n/lib/liblustreapi.so.1 strace -f -e trace=openat $(T $n)/lustre/utils/.libs/lfs find --device $MDTDEV -type d 2>&1 >/dev/null | grep 'scan_osd_' | grep -v ENOENT | head -2 | tr '\n' ' ')"
done

echo "=== fixture: files on lfst, and a second filesystem 'lustre'"
rm -rf $M/hl $M/cl0926 $M/sk
lfs mkdir -i 0 $M/hl && echo x > $M/hl/f0 && ln $M/hl/f0 $M/hl/hardlink && echo y > $M/hl/solo
lfs mkdir -i 0 $M/sk && echo z > $M/sk/victim && echo w > $M/sk/keeper
NID=$(lctl list_nids | head -1)
truncate -s 300M /tmp/lab0926-ls-mdt; truncate -s 400M /tmp/lab0926-ls-ost
LM=$(losetup -f --show /tmp/lab0926-ls-mdt); LO=$(losetup -f --show /tmp/lab0926-ls-ost)
mkfs.lustre --reformat --fsname=lustre --mdt --index=0 --mgsnode=$NID $LM > $L/mkfs-mdt.txt 2>&1 || echo "mkfs mdt failed"
mkfs.lustre --reformat --fsname=lustre --ost --index=0 --mgsnode=$NID $LO > $L/mkfs-ost.txt 2>&1 || echo "mkfs ost failed"
mkdir -p /mnt/lab-ls-mdt /mnt/lab-ls-ost /mnt/lustre
mount -t lustre $LM /mnt/lab-ls-mdt && mount -t lustre $LO /mnt/lab-ls-ost && mount -t lustre $NID:/lustre /mnt/lustre || echo "second fs mount failed"
mkdir -p /mnt/lustre/other && echo o > /mnt/lustre/other/ofile
sync; sleep 2
lctl dl | awk '{print "  " $3, $4}' | grep -E 'osd|mdt |obdfilter'
mount -t lustre | awk '{print "  mounted: " $1 " on " $3}'

echo "=== 68415: sc_type_mask with _CLEAR"
MDT=lfst-MDT0000
lctl set_param mdd.$MDT.changelog_mask=+CREAT > /dev/null
UN=$(lctl --device $MDT changelog_register -m ALL -n); UO=$(lctl --device $MDT changelog_register -m ALL -n)
echo "  users: new=$UN old=$UO"
lfs mkdir -i 0 $M/cl0926; for i in 1 2 3 4 5; do touch $M/cl0926/c$i; done; rm $M/cl0926/c1 $M/cl0926/c2
uidx() { lctl get_param -n mdd.$MDT.changelog_users | awk -v u=$1 '$1==u{print $2}'; }
for n in new old; do
	[ $n = new ] && U=$UN || U=$UO
	i0=$(uidx $U); r1=$($LB/clab.$n $MDT $U mask); i1=$(uidx $U)
	r2=$($LB/clab.$n $MDT $U both); i2=$(uidx $U)
	r3=$($LB/clab.$n $MDT $U clear); i3=$(uidx $U)
	echo "  $n: [$r1] idx $i0->$i1 | [$r2] idx $i1->$i2 | [$r3] idx $i2->$i3"
	echo "$r1|$r2|$r3|$i0|$i1|$i2|$i3" > $L/cl.$n
done
IFS='|' read r1 r2 r3 i0 i1 i2 i3 < $L/cl.new
case "$r1" in *rc=0*) [ "${r1##*records=}" -gt 0 ] && ok "68415 new: mask alone reads ($r1)" || bad "68415 mask alone delivered nothing" "$r1";; *) bad "68415 new: mask alone" "$r1";; esac
[[ "$r2" == *rc=-22* && "$i1" == "$i2" ]] && ok "68415 new: mask+CLEAR -> -EINVAL, user index unchanged ($i1)" || bad "68415 new: mask+CLEAR" "$r2 idx $i1->$i2"
[[ "$r3" == *rc=0* && "$i3" != "$i2" ]] && ok "68415 new: CLEAR alone clears (idx $i2->$i3)" || bad "68415 new: CLEAR alone" "$r3 idx $i2->$i3"
IFS='|' read r1 r2 r3 i0 i1 i2 i3 < $L/cl.old
[[ "$r2" == *rc=0* && "$i1" != "$i2" ]] && ok "68415 old arm: mask+CLEAR accepted and cleared (idx $i1->$i2): the defect" || bad "68415 old arm did not show the defect" "$r2 idx $i1->$i2"
lctl --device $MDT changelog_deregister $UN > /dev/null; lctl --device $MDT changelog_deregister $UO > /dev/null
lctl set_param mdd.$MDT.changelog_mask=-CREAT > /dev/null

echo "=== 68160: --device/--local refusals"
for a in "--mindepth 1" "--threads 2" "--maxdepth 1" "--xattr user.x"; do
	t=ref$(echo $a | tr -dc a-z)
	both $t find --local $a -type f
	[ "$(rc $t new)" = 95 ] && [ $(grep -c . $L/$t.new.err) = 1 ] && ! grep -q '^# ' $L/$t.new.err &&
		ok "68160 --local $a: one refusal, rc 95, no target opened ($(cat $L/$t.new.err))" || bad "68160 --local $a" "$(cat $L/$t.new.err | head -3)"
done
both refdev find --device $MDTDEV --mindepth 1
[ "$(rc refdev new)" = 95 ] && grep -q "describe a walk" $L/refdev.new.err && ok "68160 --device --mindepth 1 refused, rc 95" || bad "68160 --device --mindepth" "$(cat $L/refdev.new.err)"
both mgs find --target MGS
[ "$(rc mgs new)" = 22 ] && grep -q "'MGS' is not an MDT or an OST" $L/mgs.new.err && ok "68160 --target MGS -> EINVAL: $(cat $L/mgs.new.err)" || bad "68160 --target MGS" "$(cat $L/mgs.new.err)"
both nomdt find --target lfst-MDT0009
grep -q "no target 'lfst-MDT0009' mounted here" $L/nomdt.new.err && [ "$(rc nomdt new)" = 19 ] && ok "68160 an MDT name not mounted still says 'no target ... mounted here' rc 19" || bad "68160 --target lfst-MDT0009" "$(cat $L/nomdt.new.err)"
both ls find --device $MDTDEV --ls
grep -q "%p" $L/ls.new.err && [ "$(rc ls new)" = 95 ] && ok "68160 --device --ls refused by the library (rc 95): $(head -1 $L/ls.new.err)" || bad "68160 --ls" "$(cat $L/ls.new.err)"
grep -q -- '--ls$' $(T new)/Documentation/man1/lfs-find.1 && grep -A2 -- '^.B --ls$' $(T new)/Documentation/man1/lfs-find.1 | grep -q "its format ends in" && ok "68160 lfs-find.1 lists --ls among the refused" || bad "68160 man page --ls"
both livedev find --device $MDTDEV -type f
nf=$(find $M -type f 2>/dev/null | wc -l)
echo "  client sees $nf files on lfst; device scan of MDT0000 new=$(wc -l < $L/livedev.new.out) old=$(wc -l < $L/livedev.old.out)"
[ "$(rc livedev new)" = 0 ] && [ $(wc -l < $L/livedev.new.out) -gt 0 ] && ok "68160 a normal --device find works on the live MDT ($(wc -l < $L/livedev.new.out) files)" || bad "68160 normal --device find" "$(cat $L/livedev.new.err)"

echo "=== 68288: naming"
both xdev find --device $MDTDEV --fid2path /mnt/lustre -type f
grep -q "is a target of 'lfst', not of 'lustre'" $L/xdev.new.err && [ "$(rc xdev new)" != 0 ] && ok "68288 target mismatch: $(head -1 $L/xdev.new.err | cut -c1-200)" || bad "68288 mismatch message" "$(cat $L/xdev.new.err)"
both ostpaths find --local --ost 0 --paths -type f
[ "$(rc ostpaths new)" = 22 ] && grep -q "names MDT objects only" $L/ostpaths.new.err && ok "68288 --local --ost --paths refused rc 22" || bad "68288 --local --ost --paths" "$(cat $L/ostpaths.new.err)"
both locpaths find --local --paths -type f
[ "$(rc locpaths new)" = 0 ] && ok "68288 --local --paths alone still runs (rc 0, $(wc -l < $L/locpaths.new.out) lines)" || bad "68288 --local --paths" "$(head -3 $L/locpaths.new.err)"
both locost find --local --ost 0 -type f
[ "$(rc locost new)" = 0 ] && ok "68288 --local --ost 0 alone still runs (rc 0)" || bad "68288 --local --ost 0" "$(head -3 $L/locost.new.err)"
# --local --fid2path MOUNT, and FSNAME from a cwd inside the other mount
both f2pm find --local --fid2path $M -type f
(cd /mnt/lustre && both f2pf find --local --fid2path lfst -type f)
(cd $M && both f2pl find --local --fid2path /mnt/lustre -type f)
for t in f2pm f2pf f2pl; do for n in new old; do
	echo "  $t $n targets read: $(grep '^# ' $L/$t.$n.err | awk '{print $2}' | tr '\n' ' ')  failed: $(grep -c 'failed for' $L/$t.$n.err)"; done; done
chk_f2p() { local t=$1 fs=$2 other=$3 mnt=$4
	[ "$(rc $t new)" = 0 ] && ! grep '^# ' $L/$t.new.err | grep -q "$other-" && grep '^# ' $L/$t.new.err | grep -q "$fs-MDT0000" &&
	! grep -v "^$mnt/" $L/$t.new.out | grep -q . && [ $(wc -l < $L/$t.new.out) -gt 0 ]; }
chk_f2p f2pm lfst lustre $M && grep -qx "$M/hl/f0" $L/f2pm.new.out && ok "68288 --local --fid2path $M: only lfst targets, rc 0, paths under $M" || bad "68288 --local --fid2path $M" "$(head -4 $L/f2pm.new.err)"
chk_f2p f2pf lfst lustre $M && ok "68288 --local --fid2path lfst (bare fsname, cwd /mnt/lustre): only lfst targets, rc 0" || bad "68288 --local --fid2path lfst from /mnt/lustre" "$(head -4 $L/f2pf.new.err)"
chk_f2p f2pl lustre lfst /mnt/lustre && grep -qx /mnt/lustre/other/ofile $L/f2pl.new.out && ok "68288 --local --fid2path /mnt/lustre (cwd in lfst): only lustre targets, rc 0" || bad "68288 --local --fid2path /mnt/lustre" "$(head -4 $L/f2pl.new.err)"
[ "$(rc f2pm old)" != 0 ] && grep -q 'failed for' $L/f2pm.old.err && ok "68288 old arm: --local --fid2path read the other filesystem's targets and failed (rc $(rc f2pm old))" || echo "  NOTE old arm f2pm rc=$(rc f2pm old)"

echo "=== 68288: llapi_scan_rec_path() on a stopped OST's internal records"
umount $OSTMNT && echo "  OST0000 stopped ($OSTDEV)"
timeout -s KILL 120 $LB/rpath.new $OSTDEV $M > $L/rpath.new.txt 2>&1; echo "  new exit $?"
grep -E 'ask|scan rc|class' $L/rpath.new.txt | head -12 | sed 's/^/    /'
grep -q 'scan rc=0' $L/rpath.new.txt && grep -q 'class=1' $L/rpath.new.txt && ! grep 'ask class=1' $L/rpath.new.txt | grep -v 'rc=-2 ' | grep -q . &&
	ok "68288 new: every CLS_INTERNAL record -> -ENOENT, no wait ($(grep -c 'ask class=1' $L/rpath.new.txt) records)" || bad "68288 rec_path on CLS_INTERNAL" "$(tail -5 $L/rpath.new.txt)"
t0=$(date +%s); timeout -s KILL 45 $LB/rpath.old $OSTDEV $M > $L/rpath.old.txt 2>&1; e=$?; t1=$(date +%s)
echo "  old exit $e after $((t1-t0))s"; grep -E 'ask|scan rc' $L/rpath.old.txt | head -6 | sed 's/^/    /'
[ $e = 137 ] && ok "68288 old arm: waited on the stopped OST until killed at 45s (the defect)" || echo "  NOTE old arm did not hang (exit $e)"
mount -t lustre $OSTDEV $OSTMNT && echo "  OST0000 back"
sleep 5; ls -la $M/hl > /dev/null && echo "  client still answers"

echo "=== teardown of both filesystems"
umount /mnt/lustre; umount /mnt/lab-ls-ost; umount /mnt/lab-ls-mdt
losetup -d $LM $LO
cd /usr/lib64/lustre/tests
env FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre timeout 300 bash ./llmountcleanup.sh > $L/cleanup.txt 2>&1; echo "  cleanup rc=$?"
mount -t lustre | awk '{print "  LEFT MOUNTED: " $3}'
for m in $(dmsetup ls | grep flakey | cut -f1); do dmsetup remove $m; done
for d in $(losetup -a | grep -E '/tmp/lfst-|lab0926' | cut -d: -f1); do losetup -d $d; done

echo "=== on the stopped lfst MDT image (quiescent file)"
IMG=/tmp/lfst-mdt1
for a in "! --name f0" "--name hardlink" "--name f0" "--name solo" ""; do
	t=hl$(echo "$a" | tr -dc a-z0-9)
	both $t find --device $IMG --paths --type f $a
	for n in new old; do echo "    $n: $(grep '/hl/' $L/$t.$n.out | sort | tr '\n' ' ')"; done
done
grep -qx /hl/hardlink $L/hlnamef0.new.out && ! grep -q '/hl/f0' $L/hlnamef0.new.out && grep -qx /hl/solo $L/hlnamef0.new.out &&
	ok "68288 '! --name f0' prints /hl/hardlink and /hl/solo" || bad "68288 ! --name f0" "$(grep /hl/ $L/hlnamef0.new.out)"
[ "$(grep /hl/ $L/hlnamehardlink.new.out)" = /hl/hardlink ] && ok "68288 '--name hardlink' prints /hl/hardlink" || bad "68288 --name hardlink" "$(grep /hl/ $L/hlnamehardlink.new.out)"
grep -q '/hl/f0' $L/hlnamehardlink.old.out && ok "68288 old arm printed /hl/f0 for --name hardlink (the defect)" || echo "  NOTE old arm hardlink: $(grep /hl/ $L/hlnamehardlink.old.out)"
cmp -s $L/hl.new.out $L/hl.old.out && cmp -s $L/hlnamesolo.new.out $L/hlnamesolo.old.out && ok "68288 no --name, --name solo: new = old" || bad "68288 unchanged cases differ"
both stopdev find --device $IMG -type f
[ "$(rc stopdev new)" = 0 ] && [ $(wc -l < $L/stopdev.new.out) -gt 0 ] && cmp -s $L/stopdev.new.out $L/stopdev.old.out && ok "68160 --device find on the stopped MDT: $(wc -l < $L/stopdev.new.out) files, new = old" || bad "68160 stopped --device find"

echo "=== 68159: the skipped-objects warning names the target"
SK=/tmp/lab0926-skip.img; cp --sparse=always $IMG $SK
debugfs -w -R "sif /ROOT/sk/victim links_count 0" $SK 2>&1 | grep -v '^debugfs'
both skip find --device $SK -type f
grep -q "^.*$SK: 1 of [0-9]* objects were skipped" $L/skip.new.err && ok "68159 warning: $(grep skipped $L/skip.new.err | cut -c1-200)" || bad "68159 skip warning" "$(cat $L/skip.new.err)"
grep skipped $L/skip.old.err | sed 's/^/    old: /'
grep -q '/sk/keeper\|keeper' $L/skip.new.out; rm -f $SK

echo "=== tally: PASS $pass FAIL $fail"
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1
echo "== end $(date '+%F %T')"
echo "ARMS RUN DONE"
