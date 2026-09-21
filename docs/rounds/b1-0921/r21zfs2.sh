#!/bin/bash
# ZFS, take 2.  Two corrections to the first run:
#   - the striped-directory arm is A (r0920-tip, before the withholding) vs
#     C (r0921b-tip).  B already withholds, so B-vs-C showed nothing.
#   - the master has to be on MDT0000 so the scan can reach it in the pool
#     that exports cleanly: -i 0.
# Plus: every object on a ZFS MDT came back attrs=no, where ldiskfs says
# attrs=yes for all 46.  That is the round-21 gate reporting what the MDT
# declared, so this asks whether a ZFS MDT declares flags at all.
set -u
T=${T:-/home/nishida/lustre-0918}
M=${M:-/mnt/lustre}
H=/home/nishida
L=/tmp/r21lab
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }
run() { local arm=$1; shift; LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"; }

cd $T/lustre/tests || exit 1
if ! mount -t lustre | grep -q "on $M "; then
	./llmountcleanup.sh > $L/z2-clean0.log 2>&1 || true
	MDSCOUNT=2 OSTCOUNT=1 FSTYPE=zfs ./llmount.sh > $L/z2-llmount.log 2>&1 || true
	mount -t lustre | grep -q "on $M " ||
		{ echo "no mount"; tail -20 $L/z2-llmount.log; exit 1; }
fi
D=$M/r21z2
rm -rf $D; mkdir -p $D
# master on MDT0000 = the lustre-mdt1 pool
$H/armC/lfs setdirstripe -c 2 -i 0 $D/zs2 || exit 1
touch $D/zs2/x
touch $D/imm2; chattr +i $D/imm2 2>/dev/null || echo "  (chattr +i failed on zfs)"
sync
echo "=== client: $(stat -c 'size=%s blocks=%b' $D/zs2)   master MDT: $($H/armC/lfs getstripe -m $D/zs2 2>/dev/null)"
echo "=== is the immutable bit visible through the mount?"
lsattr -d $D/imm2 2>&1 | head -1
for arm in A C; do
	echo "  arm $arm --attrs Immutable: [$(run $arm $H/arm$arm/lfs find $D --attrs Immutable 2>&1 | tr '\n' ' ')]"
done
echo "=== and what the record says for it:"
run C $H/scanrec $D 2>/dev/null | grep -E "imm2|zs2" | sed 's/^/    /'

echo "=== stopping and exporting"
./llmountcleanup.sh > $L/z2-clean.log 2>&1
for p in $(zpool list -H -o name 2>/dev/null); do
	zpool export $p 2>/dev/null || zpool export -f $p 2>/dev/null ||
		echo "  could not export $p"
done
echo "  still imported: [$(zpool list -H -o name 2>/dev/null | tr '\n' ' ')]"

MDT=lustre-mdt1/mdt1
for arm in A C; do
	run $arm $H/arm$arm/lfs find --device $MDT --search /tmp -name zs2 \
	    -printf '%s %b\n' > $L/z2dev.$arm 2>&1
	echo "  arm $arm striped dir: [$(tr '\n' '|' < $L/z2dev.$arm)]"
done
if diff -q $L/z2dev.A $L/z2dev.C >/dev/null; then
	bad "the striped directory answers the same in both arms" "$(cat $L/z2dev.C)"
else
	ok "the ZFS MDT stopped answering a size for the striped directory"
fi
echo "=== $pass passed, $fail failed"
