#!/bin/bash
# Stage 14: what the 2026-08-22 AI review round changed, on ldiskfs.
#
# Each check asserts the shape of the answer and not only that two runs agree
# -- an empty scan compares equal to another empty scan, which is how a void
# run reported success before.
set -e
cd ~
R=/mnt/testfs
L=~/lustre-release
T=$L/lustre/tests/llapi_scan_device_test
FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2' want '$3'"; FAIL=1; fi; }
ckn() { if [ "$2" != "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2', which is the wrong answer"; FAIL=1; fi; }

echo "=== 0. the target under test"
MDT=$(losetup -j ~/img/mdt.img 2>/dev/null | cut -d: -f1)
[ -n "$MDT" ] || { echo "no loop device for ~/img/mdt.img; attach one first"; exit 1; }
echo "  MDT is $MDT"

# One helper for the record fields the stock test binary does not print.
cat > ~/r4_dump.c <<'EOF'
/* FID, class and mtime per object; -i adds LLAPI_SCAN_F_INTERNAL. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <linux/lustre/lustre_fid.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	(void)data;
	printf(DFID" class=%u lastid=%d mtime=%lld valid=0x%llx\n",
	       PFID(&rec->sr_fid), rec->sr_class,
	       fid_is_last_id(&rec->sr_fid) ? 1 : 0,
	       (long long)rec->sr_mtime, (unsigned long long)rec->sr_valid);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	const char *dev = NULL;
	int internal = 0, i, rc;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-i") == 0)
			internal = 1;
		else
			dev = argv[i];
	}
	if (dev == NULL)
		return 2;

	memset(&sp, 0, sizeof(sp));
	sp.sp_size = sizeof(sp);
	if (internal)
		sp.sp_flags = LLAPI_SCAN_F_INTERNAL;

	rc = llapi_scan_device(dev, &sp, cb, NULL);
	if (rc < 0) {
		fprintf(stderr, "scan: %s\n", strerror(-rc));
		return 1;
	}
	return 0;
}
EOF
gcc -O2 -Wall -o ~/r4_dump ~/r4_dump.c \
	-I$L/include -I$L/include/uapi \
	-L$L/lustre/utils/.libs -llustreapi \
	-Wl,-rpath,$L/lustre/utils/.libs
echo "  built r4_dump"

##############################################################################
echo
echo "=== 1. a filesystem that is not a Lustre target is refused (EINVAL),"
echo "===    not scanned to nothing and reported as success"
##############################################################################
rm -f ~/plain.img
dd if=/dev/zero of=~/plain.img bs=1M count=64 status=none
mkfs.ext4 -q -F ~/plain.img
PLAIN=$(sudo losetup --find --show ~/plain.img)
echo "  plain ext4 on $PLAIN"
set +e
sudo $T -d "$PLAIN" > ~/plain.out 2> ~/plain.err
PLAIN_RC=$?
set -e
echo "  rc=$PLAIN_RC"; sed -n '1,4p' ~/plain.err
ckn "a plain ext4 device does not scan successfully" "$PLAIN_RC" "0"
if grep -q "names no MDT or OST" ~/plain.err; then
	echo "  PASS  the error says why"
else
	echo "  FAIL  no 'names no MDT or OST' in the error"; FAIL=1
fi
# and it must NOT be ENOTSUP, which conf-sanity 165 keys its skip off
if grep -qi "not supported" ~/plain.err; then
	echo "  FAIL  answered ENOTSUP; test_165 would skip instead of failing"; FAIL=1
else
	echo "  PASS  not ENOTSUP, so a missing backend stays distinguishable"
fi
sudo losetup -d "$PLAIN"; rm -f ~/plain.img

##############################################################################
echo
echo "=== 2. a real MDT still scans, so check 1 refused the right thing"
##############################################################################
sudo $T -d "$MDT" -l > ~/r4-mdt.fids 2> ~/r4-mdt.err || {
	cat ~/r4-mdt.err; echo "  FAIL  the MDT itself no longer scans"; exit 1; }
NOBJ=$(wc -l < ~/r4-mdt.fids)
echo "  $NOBJ objects"
if [ "$NOBJ" -gt 50 ]; then echo "  PASS  the MDT scan is not empty"
else echo "  FAIL  only $NOBJ objects; an empty scan compares equal to anything"; FAIL=1; fi

##############################################################################
echo
echo "=== 3. LAST_ID is the target's own object, not its subject matter"
##############################################################################
# Ask fid_is_last_id() rather than grepping for oid 0: it deliberately
# excludes IGIF, where the sequence is the inode number and oid 0 is only a
# generation, so an oid-0 IGIF object is an ordinary pre-2.0 file.
sudo ~/r4_dump "$MDT" > ~/r4-def.dump 2>/dev/null
sudo ~/r4_dump -i "$MDT" > ~/r4-int.dump 2>/dev/null
LEAK=$(grep -c "lastid=1" ~/r4-def.dump || true)
INT=$(grep -c "lastid=1" ~/r4-int.dump || true)
echo "  LAST_ID objects: $LEAK in the default set, $INT under --internal"
ck "no LAST_ID reaches the default set" "$LEAK" "0"
if [ "$INT" -gt 0 ]; then
	echo "  PASS  $INT of them do appear under --internal"
	# none may be class 0 (visible); internal (1) or ost_obj (2) are both
	# right, the latter when LMAC_FID_ON_OST decided before the sequence
	BADCLS=$(grep "lastid=1" ~/r4-int.dump | grep -c "class=0" || true)
	ck "no LAST_ID is classed visible" "$BADCLS" "0"
	echo "  classes seen:"
	grep "lastid=1" ~/r4-int.dump | grep -oE 'class=[0-9]+' | sort | uniq -c |
		sed 's/^/    /'
else
	echo "  NOTE  none under --internal either; this target may have no LAST_ID"
fi
# and an oid-0 IGIF object, if the target has one, must still be delivered
IGIF=$(grep -cE '^\[0x[0-9a-f]{1,8}:0x0:0x0\] .*lastid=0' ~/r4-def.dump || true)
echo "  oid-0 non-LAST_ID (IGIF) objects still delivered: $IGIF"

##############################################################################
echo
echo "=== 4. a pre-1970 timestamp survives as a negative time"
##############################################################################
# The old code read i_mtime unsigned, so 1960 came back as a 2106 date.
sudo mkdir -p $R/r4times
sudo touch -d "1960-06-15 12:00:00" $R/r4times/old.f
OLDFID=$(sudo lfs path2fid $R/r4times/old.f)
CLIENT_MTIME=$(sudo stat -c %Y $R/r4times/old.f)
echo "  $OLDFID client mtime=$CLIENT_MTIME"
if [ "$CLIENT_MTIME" -ge 0 ]; then
	echo "  NOTE  the client did not store a negative mtime; skipping the compare"
else
	sync
	sudo ~/r4_dump "$MDT" > ~/r4-times.dump 2>/dev/null
	SCAN_MTIME=$(grep -F "$OLDFID" ~/r4-times.dump |
		     grep -oE 'mtime=-?[0-9]+' | head -1 | cut -d= -f2)
	if [ -z "$SCAN_MTIME" ]; then
		echo "  FAIL  $OLDFID is not in the device scan at all"; FAIL=1
	else
		echo "  scan mtime=$SCAN_MTIME"
		ck "the device scan agrees with the client" "$SCAN_MTIME" "$CLIENT_MTIME"
		ckn "and it is not the 2106 wraparound" \
			"$SCAN_MTIME" "$(( CLIENT_MTIME + 4294967296 ))"
	fi
fi

##############################################################################
echo
echo "=== 5. an sp_flags bit the library does not define is refused"
##############################################################################
cat > ~/r4_flags.c <<'EOF'
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	(void)rec; (void)data;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	int rc;

	if (argc < 2)
		return 2;

	memset(&sp, 0, sizeof(sp));
	sp.sp_size = sizeof(sp);
	sp.sp_flags = LLAPI_SCAN_F_INTERNAL;	/* a flag it does define */
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	printf("known=%d\n", rc);

	memset(&sp, 0, sizeof(sp));
	sp.sp_size = sizeof(sp);
	sp.sp_flags = 0x8000000000000000ULL;	/* and one from some future */
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	printf("unknown=%d\n", rc);
	return 0;
}
EOF
gcc -O2 -Wall -o ~/r4_flags ~/r4_flags.c \
	-I$L/include -I$L/include/uapi \
	-L$L/lustre/utils/.libs -llustreapi \
	-Wl,-rpath,$L/lustre/utils/.libs
sudo ~/r4_flags "$MDT" > ~/r4-flags.out 2>&1 || true
cat ~/r4-flags.out
ck "a known flag is accepted" "$(grep -oP '^known=\K-?\d+' ~/r4-flags.out)" "0"
ck "an unknown flag is -EINVAL" "$(grep -oP '^unknown=\K-?\d+' ~/r4-flags.out)" "-22"

##############################################################################
echo
echo "=== 6. the object set did not shrink when i_dtime stopped being consulted"
##############################################################################
# Dropping the i_dtime test can only add objects, so a miss here means
# something else in the round went wrong.
sudo lfs find $R > ~/r4-paths.txt 2>/dev/null
: > ~/r4-client.fids
# sort -u: a hardlinked file is two names and one object, and comm would
# report the second name as a missing FID
while read -r f; do sudo lfs path2fid "$f"; done < ~/r4-paths.txt |
	sort -u > ~/r4-client.fids
sudo $T -d "$MDT" -l 2>/dev/null | sort > ~/r4-dev.fids
NCLI=$(wc -l < ~/r4-client.fids)
MISS=$(comm -23 ~/r4-client.fids ~/r4-dev.fids | wc -l)
echo "  $NCLI client FIDs, $MISS missing from the device scan"
if [ "$NCLI" -lt 10 ]; then
	echo "  FAIL  only $NCLI client FIDs; the comparison is vacuous"; FAIL=1; fi
ck "no client FID is missing from the device" "$MISS" "0"

echo
if [ "$FAIL" = "0" ]; then echo "STAGE14 OK -- ALL ROUND 4 LDISKFS CHECKS PASSED"
else echo "STAGE14 FAILED"; exit 1; fi
