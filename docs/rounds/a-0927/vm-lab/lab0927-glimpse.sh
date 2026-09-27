#!/bin/bash
# 09-27 rerun of the 68160 glimpse-probe arm: the arms script traced
# "-e trace=%stat", which strace 6.12 on the VM matched to no call at all
# (both arms' traces held only exit lines).  Named syscalls here.  Runs on
# lfst remounted with NOFORMAT=1 (lab27/g1, g2 from the arms run, 2 MB each
# on OST0000); alternates the arms twice, and counts the OST's LDLM enqueues
# with the client's OSC locks cleared first, as a second witness.
set -u
H=/home/nishida; M=/mnt/lfst; L=/tmp/lab0927-glimpse
rm -rf $L; mkdir -p $L
exec > $L/run.txt 2>&1
T() { echo $H/lab0927-$1; }
echo "== start $(date '+%F %T')"
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: modules not loaded"; exit 3; }
mount -t lustre | grep -q "on $M " || { echo "ABORT: no lfst client"; exit 4; }
lfs getstripe -i $M/lab27/g1 $M/lab27/g2 | tr '\n' ' '; stat -c '%n %s' $M/lab27/g1 $M/lab27/g2 | tr '\n' ' '; echo
enq() { lctl get_param -n ost.OSS.ost.stats | awk '$1 ~ /ldlm/ {s = s $1 "=" $2 " "} END {print s}'; }
for round in 1 2; do for n in new old; do
	lctl set_param -n ldlm.namespaces.*-osc-ffff*.lru_size=clear > /dev/null
	e0=$(enq); l0=$(lctl get_param -n ldlm.namespaces.lfst-OST0000-osc-ffff*.lock_count)
	env LUSTRE=$(T $n)/lustre LD_PRELOAD=$H/arm0927$n/lib/liblustreapi.so.1 strace -f -o $L/gl$round.$n.strace \
		-e trace=statx,newfstatat,stat,lstat,fstatat64 \
		$(T $n)/lustre/utils/.libs/lfs find --lazy $M/lab27/g1 $M/lab27/g2 --size +1G > $L/gl$round.$n.out 2> $L/gl$round.$n.err
	rc=$?
	e1=$(enq); l1=$(lctl get_param -n ldlm.namespaces.lfst-OST0000-osc-ffff*.lock_count)
	echo "  round $round $n: rc=$rc out=$(wc -l < $L/gl$round.$n.out) err=$(wc -l < $L/gl$round.$n.err); OST ldlm stats [$e0] -> [$e1]; client OST0000 locks $l0 -> $l1"
	grep -E 'lab27/g[12]"' $L/gl$round.$n.strace | sed 's/^[0-9]* */    /' | cut -c1-220
done; done
echo "== end $(date '+%F %T')"
echo "GLIMPSE RUN DONE"
