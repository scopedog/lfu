#!/bin/bash
# 09-26: sanity subtests owned by the series, at r0926b-tip, on FSNAME=lfst.
# Installed framework and modules; the tip's sanity.sh, lfs and test binaries.
set -u
H=/home/nishida; T=$H/lab0926-new; OUT=/tmp/lab0926-sanity
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T')"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
md5sum /tmp/lustre-mdt1 /tmp/lustre-mdt2 /tmp/lustre-ost1 > $OUT/fixture.before
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre
env REFORMAT=yes bash ./llmount.sh > $OUT/llmount.txt 2>&1
echo "mounted: $(mount -t lustre | grep -c 'on /mnt/lfst ') client, $(mount -t lustre | wc -l) total"
V=$(lctl get_param -n version | head -1); echo "loaded version: [$V]"
[ -n "$V" ] || { echo "ABORT: version empty"; exit 3; }
[ $(mount -t lustre | grep -c 'on /mnt/lfst ') = 1 ] || { echo "ABORT: no client mount"; tail -20 $OUT/llmount.txt; exit 4; }
# the tip's binaries over the installed ones, for this run only
B=/usr/lib64/lustre/tests
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do
	mount --bind $T/lustre/tests/.libs/$b $B/$b || echo "bind $b failed"
done
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs || echo "bind lfs failed"
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 /usr/bin/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "changelog_test loads: $(LD_TRACE_LOADED_OBJECTS=1 $B/llapi_scan_changelog_test | grep lustreapi | tr -s ' \t' ' ')"
strings $B/llapi_scan_changelog_test | grep -q "ten bad calls" && echo "bound changelog_test is the tip's"
env ONLY="56 157c 157d 160aa 160ab 160ac 160ad 160ae" LFS=$T/lustre/utils/.libs/lfs \
    bash $T/lustre/tests/sanity.sh > $OUT/sanity.txt 2>&1
echo "SANITY_RC=$?"
for b in llapi_scan_test llapi_scan_changelog_test llapi_scan_device_test; do umount $B/$b; done
umount /usr/bin/lfs
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:" $OUT/sanity.txt | cut -c1-160 > $OUT/verdicts.txt
echo "PASS $(grep -c '^PASS' $OUT/verdicts.txt)  FAIL $(grep -c 'FAIL' $OUT/verdicts.txt)  SKIP $(grep -c 'SKIP' $OUT/verdicts.txt)"
grep -E "FAIL|SKIP" $OUT/verdicts.txt
mount | grep -E '/usr/bin/lfs|lustre/tests/llapi' && echo "BIND LEFT"
echo "== end $(date '+%F %T')"
echo "SANITY RUN DONE"
