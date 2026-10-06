#!/bin/bash
# 10-06 lab, stage 6 (as root on the clone VM): the lreview fixups.
# OLD = fixup 8506d66293 (/tmp/lab1006-new), NEW = fixup2 a2d6617d53
# (/tmp/lab1006-newb).  Usage: 06-lreview.sh c1|e1
#
# C1 (68415): _CLEAR with an unregistered user -> NEW returns -ENOENT.
# E1 (68163): non-root, exported pool on unreadable vdevs -> NEW -EACCES.
set -u
ARM=$1
declare -A TR=([old]=/tmp/lab1006-new [new]=/tmp/lab1006-newb)
declare -A PR=([old]=/tmp/arm1006new [new]=/tmp/arm1006newb)
OUT=/tmp/lab1006-lr-$ARM; rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') $ARM"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "ABORT: pools imported"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before 2>/dev/null
cd /usr/lib64/lustre/tests
export LUSTRE=/usr/lib64/lustre

if [ $ARM = c1 ]; then
	for a in old new; do
		gcc -O2 -Wall -D_GNU_SOURCE -I${TR[$a]}/lustre/include -I${TR[$a]}/include \
		    -I${TR[$a]}/include/uapi -o $OUT/clh.$a /tmp/lab1006-clh.c \
		    -L${PR[$a]}/lib -Wl,-rpath,${PR[$a]}/lib -llustreapi ||
			{ echo "ABORT: harness $a"; exit 3; }
		echo "clh.$a loads: $(LD_TRACE_LOADED_OBJECTS=1 $OUT/clh.$a | grep lustreapi | tr -s ' \t' ' ')"
	done
	export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=1
	env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
	M=/mnt/lfst; MDT=lfst-MDT0000
	[ $(mount -t lustre | grep -c "on $M ") = 1 ] || { echo "ABORT: no mount"; tail $OUT/llmount.txt; exit 4; }
	U=$(lctl --device $MDT changelog_register -n); echo "registered $U"
	mkevents() { mkdir -p $M/c1; for i in $(seq 1 30); do touch $M/c1/f$1-$i; done; sync; }
	recs() { lfs changelog $MDT | wc -l; }
	mkevents a
	echo "records before: $(recs)"
	for a in old new; do
		echo "-- $a, unregistered cl9999:  $($OUT/clh.$a $MDT cl9999 2>$OUT/c1-bad.$a.err)  stderr: $(grep -c 'cannot clear' $OUT/c1-bad.$a.err) 'cannot clear' lines"
		echo "   records still there: $(recs)"
	done
	for a in old new; do
		echo "-- $a, unregistered, callback stops at 5:  $($OUT/clh.$a $MDT cl9999 5 2>/dev/null)"
	done
	for a in old new; do
		mkevents $a
		b=$(recs)
		echo "-- $a, registered $U: $($OUT/clh.$a $MDT $U 2>$OUT/c1-good.$a.err)  records $b -> $(recs)"
	done
	lctl --device $MDT changelog_deregister $U
	bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1; echo "cleanup rc=$?"
else
	ZT=/tmp/zfslab06b; rm -rf $ZT; mkdir -p $ZT
	export FSTYPE=zfs FSNAME=zfst MDSCOUNT=1 OSTCOUNT=1 TMP=$ZT
	bash ./llmount.sh > $OUT/llmount.txt 2>&1
	mount -t lustre | grep -q zfst-MDT0000 || { echo "ABORT: MDT did not mount"; tail -25 $OUT/llmount.txt; exit 4; }
	MDTDS=$(lctl get_param -n osd-zfs.zfst-MDT0000.mntdev); echo "MDT dataset $MDTDS"
	mkdir -p /mnt/zfst/d; for i in $(seq 1 20); do echo x > /mnt/zfst/d/f$i; done
	sync; sleep 10
	bash ./llmountcleanup.sh > $OUT/cleanup.txt 2>&1
	echo "cleanup rc=$?; pools $(zpool list -H 2>/dev/null | wc -l)"
	for a in old new; do cp ${PR[$a]}/lib/lustre/scan_osd_zfs.so.orig ${PR[$a]}/lib/lustre/scan_osd_zfs.so; done
	ls -la $ZT | head
	chmod 0755 $ZT; chmod 0600 $ZT/*
	E=$ZT/empty; mkdir -p $E; chmod 0755 $E
	scan() {	# arm user label ds search
		local a=$1 u=$2 l=$3 ds=$4 se=$5
		local cmd="env LUSTRE=${TR[$a]}/lustre LD_PRELOAD=${PR[$a]}/lib/liblustreapi.so.1 ${TR[$a]}/lustre/utils/.libs/lfs find --device $ds --search $se --type f"
		if [ $u = root ]; then timeout 300 $cmd > $OUT/$l.$a.out 2> $OUT/$l.$a.err
		else timeout 300 runuser -u nishida -- $cmd > $OUT/$l.$a.out 2> $OUT/$l.$a.err; fi
		printf '%-16s %s %-5s exit=%-3s stdout=%-4s stderr: %s\n' $l $a $u $? \
			"$(wc -l < $OUT/$l.$a.out)" "$(tr '\n' '|' < $OUT/$l.$a.err | cut -c1-170)"
	}
	echo "=== E1: non-root, exported pool, vdevs 0600 root"
	for a in old new; do scan $a nishida e1 $MDTDS $ZT; done
	echo "=== missing pool, unreadable vdev present (expected EACCES on NEW)"
	for a in old new; do scan $a nishida e1-missing nosuchpool/x $ZT; done
	echo "=== missing pool, readable empty search dir (ENOENT on both)"
	for a in old new; do scan $a nishida e1-empty nosuchpool/x $E; done
	echo "=== control: root, same pool"
	for a in old new; do scan $a root root $MDTDS $ZT; done
	cmp -s <(sort $OUT/root.old.out) <(sort $OUT/root.new.out) && echo "PASS root: identical" || echo "FAIL root: differ"
	[ -z "$(zpool list -H 2>/dev/null)" ] || { echo "pools left:"; zpool list; zpool export -a; }
	rm -rf $ZT
fi
md5sum -c --quiet $OUT/fixture.before && echo "lustre-* fixtures untouched"
echo "== end $(date '+%F %T')"
echo "LR RUN DONE"
