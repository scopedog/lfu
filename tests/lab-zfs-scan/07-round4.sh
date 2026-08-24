#!/bin/bash
# Stage 7: what the 2026-08-22 AI review round changed, on ZFS.
#
# The dnode-walk fix (only ESRCH ends the scan) cannot be fault-injected here
# without a corrupted pool, so what this proves is that the rewritten loop
# still delivers the whole object set; the acceptance run in 05 is the rest of
# that evidence.
set -e
cd ~
L=~/lustre-release
T=$L/lustre/tests/llapi_scan_device_test
POOL=${POOL:-lfu-mdt}
DS=${DS:-$POOL/mdt0}
FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2' want '$3'"; FAIL=1; fi; }
ckn() { if [ "$2" != "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2', which is the wrong answer"; FAIL=1; fi; }

echo "=== 0. state"
zpool list 2>/dev/null || true
lsmod | grep -q "^zfs" && echo "  zfs module loaded" || echo "  zfs module NOT loaded"

##############################################################################
echo
echo "=== 1. a device path that does not exist says so (ENOENT),"
echo "===    instead of claiming its pool is in use"
##############################################################################
# scan_backend_kind() routes anything that is not a block device or a file to
# the ZFS backend, so a typo arrives here as a dataset name whose pool name is
# empty.  The old code then stat()ed /proc/spl/kstat/zfs/ -- the directory
# itself -- and answered EBUSY.
set +e
sudo $T -d /dev/vdXtypo > ~/r4-typo.out 2> ~/r4-typo.err
TYPO_RC=$?
set -e
echo "  rc=$TYPO_RC"; sed -n '1,4p' ~/r4-typo.err
ckn "a mistyped device does not succeed" "$TYPO_RC" "0"
if grep -qiE "in use|busy|export it first|ACTIVE" ~/r4-typo.err; then
	echo "  FAIL  still answers 'pool in use' for a path that does not exist"; FAIL=1
else
	echo "  PASS  does not claim the pool is in use"
fi
if grep -qiE "no such|not exist|ENOENT" ~/r4-typo.err; then
	echo "  PASS  says the thing does not exist"
else
	echo "  NOTE  message is '$(head -1 ~/r4-typo.err)'; check it reads as ENOENT"
fi

# A leading slash is the same bug by another route.
set +e
sudo $T -d /notapool/notads > ~/r4-slash.err 2>&1
SLASH_RC=$?
set -e
ckn "a leading-slash dataset name does not succeed" "$SLASH_RC" "0"
if grep -qiE "in use|busy|export it first" ~/r4-slash.err; then
	echo "  FAIL  '/notapool/notads' still reads as an active pool"; FAIL=1
else
	echo "  PASS  '/notapool/notads' does not read as an active pool"
fi

##############################################################################
echo
echo "=== 2. a real dataset still scans, so check 1 refused the right thing"
##############################################################################
# The pool cannot be exported while a Lustre target sits on it, and these
# targets are mounted by hand rather than by llmount, so llmountcleanup does
# not touch them -- unmount them the way 05-acceptance.sh does.
sudo umount /mnt/lfufs 2>/dev/null || true
sudo umount /mnt/ost0 /mnt/ost1 2>/dev/null || true
sudo umount /mnt/mdt0 2>/dev/null || true
sleep 2
sudo zpool export $POOL || {
	echo "  FAIL  cannot export $POOL; something still holds it"
	zpool list; FAIL=1; }
sudo $T -d "$DS" -l > ~/r4-zfs.fids 2> ~/r4-zfs.err || {
	cat ~/r4-zfs.err; echo "  FAIL  the dataset itself no longer scans"; FAIL=1; }
NOBJ=$(wc -l < ~/r4-zfs.fids 2>/dev/null || echo 0)
echo "  $NOBJ objects from $DS"
if [ "$NOBJ" -gt 20 ]; then echo "  PASS  the ZFS scan is not empty"
else echo "  FAIL  only $NOBJ objects; an empty scan compares equal to anything"; FAIL=1; fi

##############################################################################
echo
echo "=== 3. LAST_ID is classed internal here too"
##############################################################################
# scan_classify() is in liblustreapi_scan_device.c, the common layer, so the
# ldiskfs run is what proves the change; what matters here is only that this
# backend feeds it the same LMA.  Reported rather than asserted, because an
# oid-0 FID is not necessarily a LAST_ID -- fid_is_last_id() excludes IGIF.
LEAK=$(grep -cE '^\[0x[0-9a-f]+:0x0:0x0\]' ~/r4-zfs.fids || true)
echo "  oid-0 FIDs in the ZFS default set: $LEAK (see stage 14 for the assertion)"

sudo zpool import -d /dev $POOL 2>/dev/null || true

##############################################################################
echo
echo "=== 4. the spec's osd-zfs-mount file list is built from what was built"
##############################################################################
# @SCAN_ZFS_PLUGIN@ used to freeze the answer at spec-generation time, so a
# rebuild on a differently-configured host either packaged a file that was not
# built or left one unpackaged.  Both are fatal to rpmbuild, so building the
# rpms is the test.
cd $L
echo "  is the plugin built here?"
ls -la lustre/utils/scan_zfs.so 2>/dev/null || echo "    no scan_zfs.so in the build tree"
if grep -qE '^%files osd-zfs-mount -f lustre-osd-zfs-mount\.files' lustre.spec; then
	echo "  PASS  %files osd-zfs-mount takes a generated list"
else
	echo "  FAIL  %files osd-zfs-mount is not built from a generated list"
	grep -n -A3 '%files osd-zfs-mount' lustre.spec | sed 's/^/    /'; FAIL=1
fi
# nothing unsubstituted may be left anywhere in the generated spec
LEFT=$(grep -oE '@[A-Z_]+@' lustre.spec | sort -u | tr '\n' ' ')
if [ -z "$LEFT" ]; then echo "  PASS  no unsubstituted @TOKEN@ in lustre.spec"
else echo "  FAIL  unsubstituted tokens left: $LEFT"; FAIL=1; fi
echo "  building rpms (the only real test of the %files change)"
make rpms > /tmp/rpms.log 2>&1 && RPM_RC=0 || RPM_RC=$?
if [ "$RPM_RC" != "0" ] &&
   grep -q "Failed build dependencies" /tmp/rpms.log; then
	# kmod-zfs-devel does not exist for a DKMS zfs install, which is what
	# this lab has.  Not a defect in the change: the check simply cannot
	# run here, and saying so is better than a red that means nothing.
	echo "  SKIP  make rpms needs build deps this host has not:"
	sed -n '/Failed build dependencies/,+3p' /tmp/rpms.log | sed 's/^/        /'
	echo "        the %files change is unverified by rpmbuild; it needs a"
	echo "        kABI-kmod zfs host rather than a DKMS one"
elif [ "$RPM_RC" != "0" ]; then
	echo "  FAIL  make rpms failed"
	grep -nE "error|Error|Installed .but unpackaged|File not found" /tmp/rpms.log |
		head -20
	FAIL=1
else
	echo "  PASS  make rpms succeeded"
	OSDZFS=$(find ~/rpmbuild/RPMS -name "*osd-zfs-mount*.rpm" 2>/dev/null | head -1)
	if [ -n "$OSDZFS" ]; then
		echo "  $OSDZFS contains:"
		rpm -qlp "$OSDZFS" 2>/dev/null | sed 's/^/    /'
		if ls lustre/utils/scan_zfs.so >/dev/null 2>&1; then
			if rpm -qlp "$OSDZFS" 2>/dev/null | grep -q scan_zfs.so; then
				echo "  PASS  the built plugin is packaged"
			else
				echo "  FAIL  scan_zfs.so was built but is not in the rpm"; FAIL=1
			fi
		else
			if rpm -qlp "$OSDZFS" 2>/dev/null | grep -q scan_zfs.so; then
				echo "  FAIL  the rpm names a scan_zfs.so that was not built"; FAIL=1
			else
				echo "  PASS  no plugin built, none packaged"
			fi
		fi
	else
		echo "  NOTE  no osd-zfs-mount rpm produced; check /tmp/rpms.log"
	fi
fi

echo
if [ "$FAIL" = "0" ]; then echo "STAGE7 OK -- ALL ROUND 4 ZFS CHECKS PASSED"
else echo "STAGE7 FAILED"; exit 1; fi
