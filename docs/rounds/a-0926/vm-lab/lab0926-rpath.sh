#!/bin/bash
# 09-26 rerun: the '! --name f0' case (tag clash in the arms script), and
# llapi_scan_rec_path() on a stopped OST (harness lacked ss_size).
set -u
H=/home/nishida; M=/mnt/lfst; L=/tmp/lab0926-rpath; LB=$H/lab0926
rm -rf $L; mkdir -p $L; exec > $L/run.txt 2>&1
T() { echo $H/lab0926-$1; }
lfs_() { local n=$1; shift; env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0926$n/lib/liblustreapi.so.1 $(T $n)/lustre/utils/.libs/lfs "$@"; }
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: mounted"; exit 2; }
for n in new old; do echo "  ! --name f0 $n: $(lfs_ $n find --device /tmp/lfst-mdt1 --paths --type f ! --name f0 2>&1 | grep /hl/ | sort | tr '\n' ' ') rc=${PIPESTATUS[0]}"; done
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env NOFORMAT=1 bash ./llmount.sh > $L/llmount.txt 2>&1
echo "mounted: $(mount -t lustre | wc -l); version [$(lctl get_param -n version | head -1)]"
ls $M/hl
OSTDEV=$(lctl get_param -n osd-*.lfst-OST0000.mntdev); OSTMNT=$(mount | awk -v d=$OSTDEV '$1==d{print $3}')
lfs getstripe -i $M/hl/f0 $M/sk/keeper 2>&1 | tr '\n' ' '; echo
umount $OSTMNT && echo "  OST0000 stopped ($OSTDEV on $OSTMNT)"
t0=$(date +%s); timeout -s KILL 120 $LB/rpath.new $OSTDEV $M > $L/rpath.new.txt 2>&1; echo "  new exit $? after $(( $(date +%s)-t0 ))s"
cat $L/rpath.new.txt | head -30
t0=$(date +%s); timeout -s KILL 45 $LB/rpath.old $OSTDEV $M > $L/rpath.old.txt 2>&1; echo "  old exit $? after $(( $(date +%s)-t0 ))s"
cat $L/rpath.old.txt | head -30
ps -eo pid,stat,cmd | grep '[r]path\.' && echo "  RPATH PROCESS LEFT"
mount -t lustre $OSTDEV $OSTMNT && echo "  OST0000 back"
sleep 5; ls $M/hl > /dev/null && echo "  client answers"
env timeout 300 bash ./llmountcleanup.sh > $L/cleanup.txt 2>&1; echo "  cleanup rc=$?"
mount -t lustre | awk '{print "  LEFT MOUNTED: " $3}'
for m in $(dmsetup ls | grep flakey | cut -f1); do dmsetup remove $m; done
for d in $(losetup -a | grep -E '/tmp/lfst-|lab0926' | cut -d: -f1); do losetup -d $d; done
echo "== end $(date '+%F %T')"; echo "RPATH RUN DONE"
