#!/bin/bash
# Round 3 (2026-09-13) lab: A/B probes for aa575ca1 and fd5bc71b, the
# sanity 160ac /dev/full assertion against the unfixed library (must fail),
# then sanity 157c 157d 160aa-ad and conf-sanity 300-304 on the fixed arm.
set -u
T=/home/nishida/lustre-68160
U=/home/nishida/r3-unfixed
F=/home/nishida/r3-fixed
OUT=/tmp/vmr3
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date +%T) tree $(git -C $T rev-parse --short HEAD) U=$(cat $U/SHA) F=$(cat $F/SHA)"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-ost1 /tmp/lustre-ost2 > $OUT/fixture.before
for a in U F; do
	d=${!a}
	echo "--- arm $a loads: $(LD_PRELOAD=$d/liblustreapi.so.1 LD_TRACE_LOADED_OBJECTS=1 $T/lustre/utils/.libs/lfs | grep lustreapi | tr -s ' \t' ' ')"
done
# the tree's test programs ahead of the installed ones; the framework adds
# $LUSTRE/tests only when PATH does not already name it
TPATH=$T/lustre/tests:/usr/lib64/lustre/tests:$PATH

cleanup() {
	env FSNAME=lfsc bash /usr/lib64/lustre/tests/llmountcleanup.sh > $OUT/cleanup-$1.txt 2>&1
	echo "CLEANUP_$1=$?"
	for m in mds1_flakey ost1_flakey ost2_flakey; do dmsetup remove $m 2>/dev/null; done
}

cd /usr/lib64/lustre/tests
env FSNAME=lfsc bash ./llmount.sh > $OUT/llmount.txt 2>&1
echo "LLMOUNT_RC=$?"
MNT=$(mount | awk '$5 == "lustre" && $1 ~ /:\/lfsc$/ {print $3; exit}')
echo "client at: ${MNT:-none}; loaded version: '$(lctl get_param -n version 2>/dev/null | head -1)'"
if [ -n "$MNT" ]; then
	mkdir -p $MNT/r3 && chmod 777 $MNT/r3

	echo "--- aa575ca1: sc_got under a resolve"
	for a in U F; do
		d=${!a}
		printf "%s: " $a
		LD_PRELOAD=$d/liblustreapi.so.1 /home/nishida/r3-gotprobe lfsc-MDT0000 $MNT
		echo "RC_got_$a=$?"
	done

	echo "--- fd5bc71b: LL_IOC_GETOBDCOUNT fails"
	for a in U F; do
		d=${!a}
		LD_PRELOAD=/home/nishida/r3-shim.so:$d/liblustreapi.so.1 \
			$T/lustre/utils/.libs/lfs find $MNT --since 1h > $OUT/obd-$a.txt 2>&1
		echo "RC_obd_$a=$? :: $(head -c 400 $OUT/obd-$a.txt | tr '\n' '|')"
	done
	LD_PRELOAD=$F/liblustreapi.so.1 $T/lustre/utils/.libs/lfs find $MNT --since 1h > $OUT/obd-ctl.txt 2>&1
	echo "RC_obd_control_noshim=$? :: $(head -c 300 $OUT/obd-ctl.txt | tr '\n' '|')"

	echo "--- llapi_scan_test 17 (trailing slash on mnt_path)"
	LD_PRELOAD=$F/liblustreapi.so.1 timeout 300 $T/lustre/tests/.libs/llapi_scan_test -d $MNT/r3 -t 17
	echo "RC_t17=$?"

	echo "--- llapi_scan_changelog_test 4 (nine refusals)"
	LD_PRELOAD=$F/liblustreapi.so.1 timeout 300 $T/lustre/tests/.libs/llapi_scan_changelog_test -m lfsc-MDT0000 -d $MNT -o 4
	echo "RC_cl4=$?"

	echo "--- usage exits non-zero now"
	LD_PRELOAD=$F/liblustreapi.so.1 $T/lustre/tests/.libs/llapi_scan_changelog_test > /dev/null 2>&1
	echo "RC_usage_F=$? (want 1)"
	LD_PRELOAD=$U/liblustreapi.so.1 $U/llapi_scan_changelog_test > /dev/null 2>&1
	echo "RC_usage_U=$? (was 0)"
	rm -rf $MNT/r3
fi
cleanup probes

echo "--- sanity 160ac, new test, UNFIXED library: the /dev/full case must fail"
env FSNAME=lfsc ONLY=160ac PATH=$TPATH LUSTRE=/usr/lib64/lustre \
    LFS=$T/lustre/utils/lfs LD_PRELOAD=$U/liblustreapi.so.1 \
    bash $T/lustre/tests/sanity.sh > $OUT/s160ac-U.txt 2>&1
echo "SANITY_160ac_U=$?"
grep -E "^(PASS|FAIL|SKIP)|error:" $OUT/s160ac-U.txt | cut -c1-200 | head -6
cleanup s160acU

echo "--- sanity 157c 157d 160aa 160ab 160ac 160ad, FIXED library"
env FSNAME=lfsc ONLY="157c 157d 160aa 160ab 160ac 160ad" PATH=$TPATH \
    LUSTRE=/usr/lib64/lustre LFS=$T/lustre/utils/lfs \
    LD_PRELOAD=$F/liblustreapi.so.1 \
    bash $T/lustre/tests/sanity.sh > $OUT/sanity-F.txt 2>&1
echo "SANITY_F=$?"
grep -E "^(PASS|FAIL|SKIP)|error:" $OUT/sanity-F.txt | cut -c1-200 | head -20
cleanup sanityF

echo "--- conf-sanity 300-304, FIXED library"
env FSNAME=lfsc ONLY="300 301 302 303 304" PATH=$TPATH \
    LUSTRE=/usr/lib64/lustre LFS=$T/lustre/utils/lfs \
    SCANNER=$T/lustre/tests/llapi_scan_device_test \
    LD_PRELOAD=$F/liblustreapi.so.1 \
    bash $T/lustre/tests/conf-sanity.sh > $OUT/cs.txt 2>&1
echo "CS_RC=$?"
grep -E "^(PASS|FAIL|SKIP)|llapi_scan_device_test.*(fail|assertion)" $OUT/cs.txt | head -10
cleanup cs

/usr/sbin/lustre_rmmod > /dev/null 2>&1
for d in $(losetup -a | grep "/tmp/lfsc-" | cut -d: -f1); do losetup -d $d; done
mount | grep ' type lustre' | awk '{print "left mounted: "$3}'
md5sum /tmp/lustre-mdt1 /tmp/lustre-ost1 /tmp/lustre-ost2 > $OUT/fixture.after
cmp -s $OUT/fixture.before $OUT/fixture.after && echo "fixture untouched" || echo "FIXTURE CHANGED"
echo "== end $(date +%T)"
