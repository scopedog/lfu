#!/bin/bash
# 09-27 follow-up: conf-sanity 300 on ZFS at r0927-tip 719b60f73e (68163 =
# 0439ba0ba2), ZFS-capable arm ~/lab0927z-new, prefix ~/arm0927znew.
# MODE=ok      the arm's own scan_osd_zfs.so
# MODE=broken  a truncated copy bind-mounted over it: must FAIL, not SKIP
# MODE=garbage a non-ELF file bind-mounted over it: must FAIL, not SKIP
# MODE=absent  an empty dir bind-mounted over PLUGIN_DIR: must SKIP
# Vdevs are files test-framework makes in TMP=/tmp/zfslab27c.
set -u
MODE=${MODE:-ok}
H=/home/nishida; T=$H/lab0927z-new; P=$H/arm0927znew; PD=$P/lib/lustre
OUT=/tmp/lab0927f-confz-$MODE; ZT=/tmp/zfslab27c
rm -rf $OUT; mkdir -p $OUT
exec > $OUT/run.txt 2>&1
echo "== start $(date '+%F %T') MODE=$MODE"
export FSTYPE=zfs FSNAME=lfsc TMP=$ZT LUSTRE=/usr/lib64/lustre
mkdir -p $ZT
cd /usr/lib64/lustre/tests
timeout 300 bash ./llmountcleanup.sh > $OUT/clean0.txt 2>&1
mount | grep -q " type lustre" && { echo "ABORT: mounted"; exit 2; }
B=/usr/lib64/lustre/tests
for b in llapi_scan_test llapi_scan_changelog_test; do mount --bind $H/lab0927-new/lustre/tests/.libs/$b $B/$b; done
mount --bind $T/lustre/tests/.libs/llapi_scan_device_test $B/llapi_scan_device_test
mount --bind $T/lustre/utils/.libs/lfs /usr/bin/lfs
case $MODE in
broken)	head -c 4096 $PD/scan_osd_zfs.so > /tmp/lab0927f-broken.so
	mount --bind /tmp/lab0927f-broken.so $PD/scan_osd_zfs.so;;
garbage) printf 'not an ELF object\n' > /tmp/lab0927f-garbage.so
	mount --bind /tmp/lab0927f-garbage.so $PD/scan_osd_zfs.so;;
absent)	mkdir -p /tmp/lab0927f-empty; mount --bind /tmp/lab0927f-empty $PD;;
esac
echo "PLUGIN_DIR now: $(ls -la $PD 2>&1 | grep -v '^total' | awk '{print $5, $NF}' | tr '\n' ' ')"
echo "lfs loads: $(LD_TRACE_LOADED_OBJECTS=1 /usr/bin/lfs | grep lustreapi | tr -s ' \t' ' ')"
echo "scanner loads: $(LD_TRACE_LOADED_OBJECTS=1 $B/llapi_scan_device_test | grep lustreapi | tr -s ' \t' ' ')"
echo "lfs is the tip's: $(strings /usr/bin/lfs | grep -c 'join its directories with')"
# a shim that logs each call, its rc and its stderr: the proof the new
# --target check ran and what it matched, which the test prints only on error
SH=$OUT/lfs-shim; cat > $SH <<SHIM
#!/bin/bash
e=\$(mktemp); $T/lustre/utils/.libs/lfs "\$@" 2> \$e; rc=\$?
echo "lfs \$* -> rc \$rc" >> $OUT/lfs-calls.txt; sed 's/^/    /' \$e >> $OUT/lfs-calls.txt
cat \$e >&2; rm -f \$e; exit \$rc
SHIM
chmod 755 $SH
env ONLY=300 LFS=$SH SCANNER=$T/lustre/tests/.libs/llapi_scan_device_test \
    bash $H/lab0927-new/lustre/tests/conf-sanity.sh > $OUT/cs.txt 2>&1
echo "CS_RC=$?"
for m in /usr/bin/lfs $B/llapi_scan_test $B/llapi_scan_changelog_test $B/llapi_scan_device_test; do umount $m; done
case $MODE in broken|garbage) umount $PD/scan_osd_zfs.so;; absent) umount $PD;; esac
echo "PLUGIN_DIR restored: $(ls $PD | tr '\n' ' ') md5 $(md5sum < $PD/scan_osd_zfs.so | cut -c1-12)"
grep -E "^(PASS|FAIL|SKIP)|: FAIL:|SKIP:|no zfs scan backend|in use|device scan backend|not refused|pool imported" $OUT/cs.txt | cut -c1-300
echo "--- lfs --target calls:"; grep -A3 -- '--target' $OUT/lfs-calls.txt
timeout 300 bash ./llmountcleanup.sh > $OUT/clean1.txt 2>&1
mount -t lustre | awk '{print "left mounted: "$3}'
echo "pools: [$(zpool list -H -o name 2>/dev/null | tr '\n' ' ')]"
mount | grep -E '/usr/bin/lfs|lustre/tests/llapi|arm0927znew' && echo "BIND LEFT"
echo "== end $(date '+%F %T')"
echo "CONFZ RUN DONE"
