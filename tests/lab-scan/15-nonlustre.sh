#!/bin/bash
# Stage 15: a directory that is not on Lustre, below a Lustre mount.
#
# This is the case the 2026-08-22 review found and the one that would have
# shipped.  llapi_scan_get_lmv() returned -ENOTTY for such a directory and
# scan_rec_gather() propagated it, so llapi_scan_cb_init() took "goto out" and
# the object was dropped with no record and no error -- and because 68095
# moves lfs find onto scan_rec_gather(), lfs find inherited it.
# get_lmd_info_fd() has an lstat() fallback for exactly this, which the early
# return was bypassing.
#
# Nothing in sanity 56* reaches it: those trees are entirely on Lustre.
set -e
cd ~
R=${R:-/mnt/testfs}
L=~/lustre-release
FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2' want '$3'"; FAIL=1; fi; }

echo "=== 0. a non-Lustre filesystem mounted below the Lustre root"
sudo mkdir -p $R/nonlustre
mountpoint -q $R/nonlustre || sudo mount -t tmpfs -o size=16m tmpfs $R/nonlustre
sudo mkdir -p $R/nonlustre/sub
sudo touch $R/nonlustre/plain.txt $R/nonlustre/sub/deeper.txt
sudo sh -c "echo hello > $R/nonlustre/plain.txt"
mount | grep " $R/nonlustre " | sed 's/^/  /'

##############################################################################
echo
echo "=== 1. lfs find still walks into it and reports what is there"
##############################################################################
set +e
sudo lfs find $R/nonlustre > ~/nl-find.out 2> ~/nl-find.err
FIND_RC=$?
set -e
echo "  rc=$FIND_RC, $(wc -l < ~/nl-find.out) paths"
sed -n '1,6p' ~/nl-find.out | sed 's/^/    /'
[ -s ~/nl-find.err ] && sed -n '1,3p' ~/nl-find.err | sed 's/^/  stderr: /'
ck "lfs find exits 0 over a non-Lustre directory" "$FIND_RC" "0"
for f in plain.txt sub sub/deeper.txt; do
	if grep -qx "$R/nonlustre/$f" ~/nl-find.out; then
		echo "  PASS  $f is reported"
	else
		echo "  FAIL  $f is missing from the walk"; FAIL=1
	fi
done

##############################################################################
echo
echo "=== 2. and a predicate over it still answers"
##############################################################################
# -type f is the cheap dirent-only path; -size needs the stat, which is the
# lstat() fallback the ENOTTY return was skipping.
set +e
sudo lfs find $R/nonlustre -type f > ~/nl-typef.out 2>&1
TYPEF_RC=$?
sudo lfs find $R/nonlustre -size +1c > ~/nl-size.out 2>&1
SIZE_RC=$?
set -e
ck "lfs find -type f exits 0" "$TYPEF_RC" "0"
ck "lfs find -size +1c exits 0" "$SIZE_RC" "0"
NF=$(grep -c . ~/nl-typef.out || true)
echo "  -type f found $NF file(s)"
if [ "$NF" -ge 2 ]; then echo "  PASS  both regular files came back"
else echo "  FAIL  expected 2 regular files, got $NF"; cat ~/nl-typef.out; FAIL=1; fi
if grep -qx "$R/nonlustre/plain.txt" ~/nl-size.out; then
	echo "  PASS  -size matched the non-empty file, so the stat fallback ran"
else
	echo "  FAIL  -size did not match plain.txt; the lstat fallback did not run"
	cat ~/nl-size.out; FAIL=1
fi

##############################################################################
echo
echo "=== 3. the namespace scanner delivers those objects rather than"
echo "===    dropping them, and the whole walk does not stop"
##############################################################################
cat > ~/nl_scan.c <<'EOF'
/* Count what llapi_scan_namespace() delivers, and note the non-Lustre ones. */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

struct acc { unsigned long n; unsigned long nl; };

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	struct acc *a = data;

	a->n++;
	if (rec->sr_path != NULL && strstr(rec->sr_path, "/nonlustre") != NULL) {
		a->nl++;
		printf("nonlustre: %s valid=0x%llx\n", rec->sr_path,
		       (unsigned long long)rec->sr_valid);
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	struct acc a = { 0, 0 };
	int rc;

	if (argc < 2)
		return 2;

	memset(&sp, 0, sizeof(sp));
	sp.sp_size = sizeof(sp);
	sp.sp_flags = LLAPI_SCAN_F_STOP_ON_ERROR;	/* the strict setting */

	rc = llapi_scan_namespace(argv[1], &sp, cb, &a);
	printf("rc=%d total=%lu nonlustre=%lu\n", rc, a.n, a.nl);
	return 0;
}
EOF
gcc -O2 -Wall -o ~/nl_scan ~/nl_scan.c \
	-I$L/include -I$L/include/uapi \
	-L$L/lustre/utils/.libs -llustreapi \
	-Wl,-rpath,$L/lustre/utils/.libs
sudo ~/nl_scan $R > ~/nl-scan.out 2>&1 || true
grep "^nonlustre:" ~/nl-scan.out | sed 's/^/    /'
tail -1 ~/nl-scan.out | sed 's/^/  /'
SRC=$(grep -oP '^rc=\K-?\d+' ~/nl-scan.out || echo missing)
STOT=$(grep -oP 'total=\K\d+' ~/nl-scan.out || echo 0)
SNL=$(grep -oP 'nonlustre=\K\d+' ~/nl-scan.out || echo 0)
# With STOP_ON_ERROR set, the old code aborted the entire walk on the first
# such directory -- so this is the assertion that matters most.
ck "the scan succeeds with STOP_ON_ERROR set" "$SRC" "0"
if [ "$STOT" -gt 50 ]; then echo "  PASS  the whole tree was walked ($STOT objects)"
else echo "  FAIL  only $STOT objects; the walk stopped early"; FAIL=1; fi
if [ "$SNL" -ge 3 ]; then
	echo "  PASS  the non-Lustre directory and its contents were delivered ($SNL)"
else
	echo "  FAIL  only $SNL non-Lustre objects delivered; expected the"
	echo "        directory, its subdirectory and two files"; FAIL=1
fi

##############################################################################
echo
echo "=== 4. lfs getdirstripe and lfs getstripe -D close the right fd"
echo "===    (cb_getstripe(), the third caller of the same reopen)"
##############################################################################
# These reach cb_get_dirstripe() through cb_getstripe().  They stop at the
# ENOTTY either way, so what the write-back changes here is not the walk but
# the descriptor: without it the traversal closes a number cb_get_dirstripe()
# already closed.  So the assertion is on the closes, not on the output.
#
# lfs getstripe -r on its own sets neither fp_get_lmv nor fp_get_default_lmv
# and never reaches the call, which is why -D is used for it here.
command -v strace >/dev/null 2>&1 || sudo dnf install -y strace >/dev/null 2>&1
for args in "getdirstripe -r" "getstripe -D -r"; do
	sudo strace -e trace=close -o ~/nl-strace.txt 		lfs $args $R/nonlustre > /dev/null 2>&1 || true
	BAD=$(grep -c EBADF ~/nl-strace.txt || true)
	echo "  lfs $args: $BAD close(s) returned EBADF"
	ck "lfs $args closes no descriptor twice" "$BAD" "0"
done

sudo umount $R/nonlustre || true
sudo rmdir $R/nonlustre 2>/dev/null || true

echo
if [ "$FAIL" = "0" ]; then echo "STAGE15 OK -- THE NON-LUSTRE DIRECTORY CASE IS COVERED"
else echo "STAGE15 FAILED"; exit 1; fi
