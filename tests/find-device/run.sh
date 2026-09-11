#!/bin/bash
# llapi_find_device() over a local ldiskfs image -- no VM, no mount, no root.
#
# There is no in-tree caller of llapi_find_device() until lfind(8) arrives
# with LU-20722, so tdev.c stands in for it: lfs_find_parse() for the
# predicates, then llapi_find_device().  The MDT fixture is tests/mkimage.sh's;
# the OST one is a relabelled copy of it, whose single LMAC_FID_ON_OST object
# becomes the subject matter once the label says OST.
#
# Needs libext2fs-dev, and the scan backend built by hand -- a
# --disable-server tree does not build it (LDISKFS_ENABLED is off).
#
# Usage: tests/find-device/run.sh <lustre-release-tree>
set -uo pipefail

T="${1:?usage: run.sh <lustre-release-tree>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$(dirname "$HERE")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CFLAGS=(-include "$T/config.h" -I "$T/include" -I "$T/include/uapi"
	-I "$T/lustre/utils" -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1
	-D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1)

# the dlopened backend, which the build does not produce for a client tree
if [ ! -f "$T/lustre/utils/scan_osd_ldiskfs.so" ]; then
	gcc -shared -fPIC -Wl,--export-dynamic \
	    -o "$T/lustre/utils/scan_osd_ldiskfs.so" \
	    "$T/lustre/utils/libscan_ldiskfs.c" "${CFLAGS[@]}" -lext2fs || exit 1
fi
export LUSTRE="$T/lustre"

gcc -o "$WORK/tdev" "$HERE/tdev.c" "$T/lustre/utils/lfs_find_parse.c" \
    "${CFLAGS[@]}" -L "$T/lustre/utils/.libs" -llustreapi \
    -Wl,-rpath,"$T/lustre/utils/.libs" || exit 1
gcc -o "$WORK/lift_want" "$HERE/lift_want.c" -I "$T/include" \
    -I "$T/include/uapi" -include "$T/config.h" -D_GNU_SOURCE -Wall -Werror || exit 1

# Build each fixture once and leave it alone: a script that mutates its own
# fixture returns plausible wrong answers.
bash "$ROOT/tests/mkimage.sh" "$WORK/mdt.img" 64M >/dev/null 2>&1 || exit 1
tune2fs -L testfs-MDT0000 "$WORK/mdt.img" >/dev/null || exit 1
cp "$WORK/mdt.img" "$WORK/ost.img"
tune2fs -L testfs-OST0003 "$WORK/ost.img" >/dev/null || exit 1

cd "$WORK"
fail=0
n() { ./tdev "$@" 2>/dev/null | wc -l; }
chk() {
	if [ "$2" = "$3" ]; then
		printf '  \033[32mPASS\033[0m %-32s %s\n' "$1" "$2"
	else
		printf '  \033[31mFAIL\033[0m %-32s got %s want %s\n' "$1" "$2" "$3"
		fail=1
	fi
}

echo "== --mdt over an MDT scan (18 objects)"
chk "--mdt 0"              "$(n mdt.img --mdt 0)" 18
chk "--mdt 1"              "$(n mdt.img --mdt 1)" 0
chk "--mdt 0,1"            "$(n mdt.img --mdt 0,1)" 18
chk "--mdt MDT0000_UUID"   "$(n mdt.img --mdt testfs-MDT0000_UUID)" 18
chk "--mdt MDT0003_UUID"   "$(n mdt.img --mdt testfs-MDT0003_UUID)" 0
# lfs.c never assigns fp_exclude_mdt -- it sets fp_exclude_obd for both -m and
# -O -- so the negated form cannot be reached through the parser.  XMDT sets it.
chk "! --mdt 0"            "$(XMDT=1 n mdt.img --mdt 0)" 0
chk "! --mdt 1"            "$(XMDT=1 n mdt.img --mdt 1)" 18
chk "! --mdt MDT0003_UUID" "$(XMDT=1 n mdt.img --mdt testfs-MDT0003_UUID)" 18

echo "== --ost over an OST scan (1 object)"
chk "--ost 3"              "$(n ost.img --ost 3)" 1
chk "--ost 5"              "$(n ost.img --ost 5)" 0
chk "! --ost 5"            "$(n ost.img ! --ost 5)" 1
chk "! --ost 3"            "$(n ost.img ! --ost 3)" 0
chk "--ost 1-5"            "$(n ost.img --ost 1-5)" 1
chk "--ost OST0003_UUID"   "$(n ost.img --ost testfs-OST0003_UUID)" 1
chk "--ost OST0007_UUID"   "$(n ost.img --ost testfs-OST0007_UUID)" 0
chk "! --ost OST0007_UUID" "$(n ost.img ! --ost testfs-OST0007_UUID)" 1

echo "== the wrong kind of target is refused, an empty answer is not an error"
./tdev ost.img --mdt 0 >/dev/null 2>&1; chk "--mdt over an OST" "$?" 1
./tdev mdt.img --ost 0 >/dev/null 2>&1; chk "--ost over an MDT" "$?" 1
./tdev ost.img --ost 5 >/dev/null 2>&1; chk "empty set exits 0" "$?" 0

echo "== a matched predicate filters nothing"
./tdev mdt.img -printf '%LF %i %Lc\n' 2>/dev/null > a
./tdev mdt.img --mdt 0 -printf '%LF %i %Lc\n' 2>/dev/null > b
chk "--mdt 0 == no predicate" "$(cmp -s a b && echo same)" same
./tdev ost.img -printf '%LF %i\n' 2>/dev/null > a
./tdev ost.img --ost 3 -printf '%LF %i\n' 2>/dev/null > b
chk "--ost 3 == no predicate" "$(cmp -s a b && echo same)" same

echo "== -printf over a target scan"
./tdev mdt.img -printf '%p\n' >/dev/null 2>&1;          chk "%p refused"  "$?" 1
./tdev mdt.img -printf 'x%%p %i\n' >/dev/null 2>&1;     chk "%%p allowed" "$?" 0
./tdev mdt.img -type f > a 2>/dev/null
./tdev mdt.img -type f -printf '[%LF]\n' > b 2>/dev/null
chk "%LF == the default output" "$(cmp -s a b && echo same)" same
chk "a line per object" "$(./tdev mdt.img -printf 'x%Lc\n' 2>/dev/null | wc -l)" 18
./lift_want | tail -1

echo "== an object with no trusted.lma: an IGIF on MDT0000 and nowhere else"
# The same image under three labels.  osd_scrub_setup() allows an IGIF on MDT0
# alone; elsewhere the object may be FID-on-OST or carry a FID a file-level
# restore invalidated, and an OST object is named by the IDIF in trusted.fid.
cp mdt.img mdt3.img && tune2fs -L testfs-MDT0003 mdt3.img >/dev/null
INTERNAL=1 ./tdev mdt.img  2>/dev/null > m0.all
INTERNAL=1 ./tdev mdt3.img 2>/dev/null > m3.all
INTERNAL=1 ./tdev ost.img  2>/dev/null > o.all
chk "same records whatever the label" \
    "$(wc -l <m0.all) $(wc -l <m3.all) $(wc -l <o.all)" "27 27 27"
# inode 12 is the first IGIF; 11 is FID_SEQ_RSVD, which fid_is_sane() wrongly
# accepted and fid_is_igif() does not -- lost+found was [0xb:0x0:0x0].
chk "MDT0000 inode 12 -> IGIF"  "$(grep -c '^\[0xc:0x0:0x0\]$' m0.all)" 1
chk "MDT0000 inode 11 -> obj:"  "$(grep -c '^obj:11$' m0.all)" 1
chk "MDT0000 no bad IGIF"       "$(grep -c '^\[0xb:0x0:0x0\]$' m0.all)" 0
chk "MDT0003 builds no IGIF"    "$(grep -c '^\[0xc:0x0:0x0\]$' m3.all)" 0
chk "MDT0003 inode 12 -> obj:"  "$(grep -c '^obj:12$' m3.all)" 1
chk "OST builds no IGIF"        "$(grep -c '^\[0xc:0x0:0x0\]$' o.all)" 0
chk "OST inode 12 -> obj:"      "$(grep -c '^obj:12$' o.all)" 1

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
