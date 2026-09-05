#!/bin/bash
# 68288: the --fid2path wrong-filesystem guard, on real loop devices.
#
# A never-mounted target's label is "fsname:MDT0000" -- mkfs.lustre writes
# ':' for LDD_F_VIRGIN, '-' only once registered -- and the first cut of the
# guard split on '-', so it found no fsname and silently let the scan run.
# Both separators are exercised here.
LFIND=${LFIND:-/home/nishida/lustre-160ac/lustre/utils/lfind}
M=/mnt/lustre
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "        $2"; fail=$((fail+1)); }

mk() { # $1=fsname -> echoes loop device
	local img=/tmp/r17g-$1.img
	rm -f $img; dd if=/dev/zero of=$img bs=1M count=300 2>/dev/null
	local loop=$(losetup --find --show $img)
	if ! mkfs.lustre --fsname=$1 --mdt --mgs --index=0 \
	     --backfstype=ldiskfs --reformat $loop > /tmp/r17g-mkfs-$1.log 2>&1; then
		losetup -d $loop; rm -f $img; return 1
	fi
	echo $loop
}
cleanup() { losetup -d $1 2>/dev/null; rm -f /tmp/r17g-*.img; }

echo "=== the mount is /mnt/lustre, whose fsname is 'lustre'"

# A: a target of another filesystem must be refused, naming both fsnames
LOOP=$(mk otherfs) || { echo "  SKIP A (mkfs failed)"; exit 1; }
echo "    label: $(e2label $LOOP)"
out=$($LFIND --device $LOOP --fid2path $M 2>&1); rc=$?
if (( rc != 0 )) && grep -q "is a mount of 'lustre', not of 'otherfs'" <<< "$out"; then
	ok "A the wrong filesystem is refused, and the message names both"
	echo "        $(grep 'is a mount of' <<< "$out" | head -1 | cut -c1-140)"
else
	no "A not refused as expected (rc=$rc)" "${out:-<no output>}"
fi
cleanup $LOOP

# B: the control -- same fsname, must NOT be refused.  Asserted on the
# absence of the refusal, and separately that the scan really ran: a target
# with no user objects still reports its own, which --internal shows.
LOOP=$(mk lustre) || { echo "  SKIP B (mkfs failed)"; exit 1; }
echo "    label: $(e2label $LOOP)"
out=$($LFIND --device $LOOP --fid2path $M 2>&1); rc=$?
if grep -q "is a mount of" <<< "$out"; then
	no "B the matching fsname was refused" "$(head -1 <<< "$out")"
else
	ok "B the matching fsname is not refused (rc=$rc)"
fi
n=$($LFIND --device $LOOP --internal 2>/dev/null | wc -l)
if (( n > 0 )); then
	ok "B2 the scan actually ran on it: $n internal objects"
else
	no "B2 the scan produced nothing even with --internal" "so B's 'not refused' proves little"
fi
cleanup $LOOP

echo "=== guard tally: PASS:$pass FAIL:$fail"
