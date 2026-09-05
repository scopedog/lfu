#!/bin/bash
# Round 17's targeted checks: the three defects with no subtest of their own.
# Run as root, with /mnt/lustre already mounted by 13-run-r17.sh's llmount.
L=${LTREE:-/home/nishida/lustre-160ac}
LFIND=$L/lustre/utils/lfind
LFS=$L/lustre/utils/lfs
M=/mnt/lustre
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

echo "=== A. 68288: a --fid2path mount of another filesystem is refused"
# A second MDT, formatted and never mounted, whose label names another
# filesystem.  The guard reads the label off the device, so no second mount
# is needed to make the mismatch.
OT=/tmp/r17-otherfs-mdt
rm -f $OT; dd if=/dev/zero of=$OT bs=1M count=200 2>/dev/null
NID=$(lctl list_nids 2>/dev/null | head -1)
if mkfs.lustre --fsname=otherfs --mdt --mgs --index=0 \
	--param=sys.timeout=20 --backfstype=ldiskfs \
	--device-size=200000 --reformat $OT > /tmp/r17-mkfs.log 2>&1; then
	out=$($LFIND --device $OT --fid2path $M -type f 2>&1); rc=$?
	if (( rc != 0 )) && grep -qi "not of\|mount of" <<< "$out"; then
		ok "A1 wrong-filesystem mount refused (rc=$rc)"
		echo "        $(head -1 <<< "$out")"
	else
		no "A1 wrong-filesystem mount was NOT refused (rc=$rc)" "$(head -2 <<< "$out")"
	fi
	# the positive control: same trick, this filesystem's own name
	OT2=/tmp/r17-samefs-mdt
	rm -f $OT2; dd if=/dev/zero of=$OT2 bs=1M count=200 2>/dev/null
	if mkfs.lustre --fsname=lustre --mdt --mgs --index=0 \
		--param=sys.timeout=20 --backfstype=ldiskfs \
		--device-size=200000 --reformat $OT2 >> /tmp/r17-mkfs.log 2>&1; then
		out2=$($LFIND --device $OT2 --fid2path $M -type f 2>&1); rc2=$?
		if grep -qi "not of\|mount of" <<< "$out2"; then
			no "A2 the matching fsname was refused too" "$(head -2 <<< "$out2")"
		else
			ok "A2 matching fsname not refused (rc=$rc2), so A1 is the guard and not a blanket failure"
		fi
	else
		echo "  SKIP  A2 (mkfs.lustre for the control failed)"
	fi
	rm -f $OT $OT2
else
	echo "  SKIP  A (mkfs.lustre failed; see /tmp/r17-mkfs.log)"
	tail -3 /tmp/r17-mkfs.log | sed 's/^/        /'
fi

echo "=== B. 68159: a small foreign layout is seen by --foreign"
D=$M/r17b; rm -rf $D; mkdir -p $D
if $LFS setstripe --foreign=none --xattr=abc $D/f 2>/tmp/r17-foreign.log; then
	sz=$(getfattr -n trusted.lov --only-values -e hex $D/f 2>/dev/null | wc -c)
	echo "        trusted.lov is about $sz hex chars"
	out=$($LFS find $D --foreign 2>&1)
	if grep -q "/f$" <<< "$out"; then
		ok "B1 lfs find --foreign sees the small foreign file"
	else
		no "B1 lfs find --foreign missed it" "got: '$out'"
	fi
	# and the scan path, which is where the 32-byte floor lived
	MDTDEV=$(cat /proc/fs/lustre/osd*/lustre-MDT0000/mntdev 2>/dev/null | head -1)
	[[ -z "$MDTDEV" ]] && MDTDEV=$(lctl get_param -n osd*.lustre-MDT0000.mntdev 2>/dev/null | head -1)
	echo "        MDT device: ${MDTDEV:-unknown} (scan needs it unmounted; reported only)"
else
	echo "  SKIP  B (setstripe --foreign not supported here)"
	tail -2 /tmp/r17-foreign.log | sed 's/^/        /'
fi

echo "=== C. 68095: %L directives stay quiet under a non-Lustre directory"
D=$M/r17c; rm -rf $D; mkdir -p $D/tmpfs
if mount -t tmpfs none $D/tmpfs 2>/dev/null; then
	touch $D/tmpfs/a $D/tmpfs/b
	err=$($LFS find $D -printf '%p %Lc\n' 2>&1 >/dev/null | grep -c "cannot get")
	if (( err == 0 )); then
		ok "C1 no 'cannot get' lines on stderr for the tmpfs files"
	else
		no "C1 $err error lines on stderr" "$($LFS find $D -printf '%p %Lc\n' 2>&1 >/dev/null | head -2)"
	fi
	# and the walk still reports the objects
	n=$($LFS find $D -printf '%p\n' 2>/dev/null | grep -c "tmpfs/")
	(( n >= 2 )) && ok "C2 the walk still reaches the $n objects under it" \
		|| no "C2 the walk reached only $n objects under the tmpfs" ""
	umount $D/tmpfs
else
	echo "  SKIP  C (could not mount tmpfs under $M)"
fi
rm -rf $M/r17b $M/r17c

echo "=== targeted tally: PASS:$pass FAIL:$fail"
