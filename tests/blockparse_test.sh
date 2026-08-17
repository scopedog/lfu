#!/bin/bash
# Check the raw inode-table parser from patches/itable-blockparse-*.patch against
# real ext4 images, in userspace and without root.
#
# osd_raw_lma() and osd_raw_attr() are lifted verbatim out of the patch and
# compiled into tests/bpval.c, so what runs here is the code that runs in the
# kernel -- only the kernel types around it are stubbed.  The images are built
# with mke2fs and debugfs, which write the on-disk format independently of any
# of our code, and every field is compared against what debugfs reports.
#
# Cases: LMA alone in the inode; no xattrs at all (must decline, so the caller
# falls back to iget); LMA in the inode while a second attribute has spilled to
# an external block (the shape of a wide-striped file on an MDT); and LMA with
# other entries either side of it.  Each is run at a 256- and a 1024-byte inode
# size, which changes both the inodes-per-block arithmetic and the size of the
# in-inode xattr area.
#
# 2026-08-17: also the three tier-0 fields the raw parser did not fill --
# crtime, projid, i_flags -- against debugfs, and osd_raw_xattr(), the generic
# in-inode lookup behind every tier-1 predicate: an inline trusted.som and
# trusted.lov come back byte-for-byte, and an attribute that debugfs pushed to
# the external block is reported absent from the inode (the caller's cue to
# take the tier-2 path) rather than found or invented.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PATCH="$HERE/../patches/itable-blockparse-v2_17_55.patch"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

for t in mke2fs debugfs dumpe2fs gcc python3; do
	command -v "$t" >/dev/null || { echo "SKIP: $t not found"; exit 0; }
done

# --- lift the two functions and the on-disk xattr definitions out of the patch
python3 - "$PATCH" > extracted.c <<'PY'
import re, sys
added = "".join(l[1:] for l in open(sys.argv[1])
                if l.startswith('+') and not l.startswith('+++'))
start = added.index('#define LFU_XATTR_MAGIC')
end = added.index('/**\n * osd_iit_iget_raw')
body = added[start:end]
# the kernel's error-return macros, unwrapped
body = re.sub(r'\bRETURN\((.*)\);', r'return (\1);', body)
body = body.replace('\tENTRY;\n', '')
sys.stdout.write(body)
PY
grep -q osd_raw_lma extracted.c || { echo "FAIL: could not lift osd_raw_lma"; exit 1; }
grep -q osd_raw_attr extracted.c || { echo "FAIL: could not lift osd_raw_attr"; exit 1; }
grep -q osd_raw_xattr extracted.c || { echo "FAIL: could not lift osd_raw_xattr"; exit 1; }

cp "$HERE/bpval.c" .
gcc -O1 -o bpval bpval.c

# --- the LMA to plant: compat 0, incompat 0, FID [0x200000401:0x1a2b3c4d:0x0]
python3 -c "
import struct,sys
sys.stdout.buffer.write(struct.pack('<IIQII', 0, 0, 0x200000401, 0x1a2b3c4d, 0))" > lma.bin
head -c 300000 /dev/urandom > payload
head -c 3000 /dev/zero | tr '\0' 'x' > big.bin
# a SOM (lazy, 2 GiB, 4 Mi blocks) and a 2-stripe LOV v1, the same encoders
# tests/mkimage.sh uses; the test compares the bytes back verbatim
python3 -c "
import struct,sys
sys.stdout.buffer.write(struct.pack('<4H2Q', 4, 0, 0, 0, 2<<30, (2<<30)//512))" > som.bin
python3 -c "
import struct,sys
b = struct.pack('<II16sIHH', 0x0BD10BD0, 1, b'\0'*16, 1<<20, 2, 0)
b += b''.join(struct.pack('<16sII', b'\0'*16, 0, o) for o in (3, 7))
sys.stdout.buffer.write(b)" > lov.bin
SOM_HEX=$(od -An -tx1 -v som.bin | tr -d ' \n')
LOV_HEX=$(od -An -tx1 -v lov.bin | tr -d ' \n')

FAIL=0
check() {  # check <what> <got> <want>
	if [ "$2" = "$3" ]; then
		echo "    ok   $1 = $2"
	else
		echo "    FAIL $1 = $2, expected $3"; FAIL=1
	fi
}

for I in 256 1024; do
	IMG=i$I.img
	truncate -s 128M $IMG
	# project is on, as mkfs.lustre formats an MDT, so i_projid is real
	mke2fs -q -t ext4 -I $I -b 4096 -F -O ^has_journal,project $IMG
	for n in 1 2 3 4 5; do debugfs -w -R "write payload f$n" $IMG >/dev/null 2>&1; done
	debugfs -w -R "ea_set -f lma.bin f1 trusted.lma"  $IMG >/dev/null 2>&1
	# f2: nothing
	debugfs -w -R "ea_set -f big.bin f3 trusted.big"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f lma.bin f3 trusted.lma"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set f4 trusted.aaa hello"       $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f lma.bin f4 trusted.lma"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set f4 user.zzz world"          $IMG >/dev/null 2>&1
	# f5: the tier-1 shape -- LMA, SOM and a small LOV all inline
	debugfs -w -R "ea_set -f lma.bin f5 trusted.lma"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f som.bin f5 trusted.som"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f lov.bin f5 trusted.lov"  $IMG >/dev/null 2>&1
	# non-default identity and mode on f1, to exercise the high halves
	debugfs -w -R "sif f1 uid 65123" $IMG >/dev/null 2>&1
	debugfs -w -R "sif f1 gid 4294967295" $IMG >/dev/null 2>&1
	# tier-0 fields the raw parser did not fill before 2026-08-17:
	# projid, crtime, and i_flags (IMMUTABLE|NODUMP = 0x50)
	debugfs -w -R "sif f1 projid 1999" $IMG >/dev/null 2>&1
	debugfs -w -R "sif f1 crtime 20200102030405" $IMG >/dev/null 2>&1
	debugfs -w -R "sif f1 flags 0x80050" $IMG >/dev/null 2>&1

	ITAB=$(dumpe2fs $IMG 2>/dev/null | grep -m1 "Inode table at" | sed 's/.*at \([0-9]*\).*/\1/')
	echo "== inode size $I (inode table at block $ITAB)"

	for n in 1 2 3 4 5; do
		INO=$(debugfs -R "stat f$n" $IMG 2>/dev/null | head -1 |
		      sed 's/Inode: \([0-9]*\).*/\1/')
		OUT=$(./bpval $IMG "$INO" "$ITAB" 32768 "$I" 1 1 som lov big)
		RC=$(echo "$OUT" | sed -n 's/^osd_raw_lma rc=//p')
		echo "  f$n (ino $INO)"
		case $n in
		2)	# no xattrs at all: must decline with -ENODATA (-61)
			check "rc" "$RC" "-61" ;;
		*)	check "rc" "$RC" "0"
			check "fid" "$(echo "$OUT" | sed -n 's/^FID \(\[[^]]*\]\).*/\1/p')" \
				"[0x200000401:0x1a2b3c4d:0x0]" ;;
		esac

		# every attribute against debugfs's own reading of the same inode
		S=$(debugfs -R "stat f$n" $IMG 2>/dev/null)
		WUID=$(echo "$S" | sed -n 's/.*User: *\([0-9]*\).*/\1/p')
		WSIZE=$(echo "$S" | sed -n 's/.*Size: *\([0-9]*\).*/\1/p' | head -1)
		WBLK=$(echo "$S" | sed -n 's/.*Blockcount: *\([0-9]*\).*/\1/p')
		WMT=$(echo "$S" | sed -n 's/^ mtime: 0x\([0-9a-f]*\):.*/\1/p')
		GUID=$(echo "$OUT" | sed -n 's/.*uid=\([0-9]*\).*/\1/p')
		GSIZE=$(echo "$OUT" | sed -n "s/^mode=.* size=\([0-9]*\).*/\1/p")
		GBLK=$(echo "$OUT" | sed -n 's/.*blocks=\([0-9]*\).*/\1/p')
		GMT=$(printf %x "$(echo "$OUT" | sed -n 's/.*mtime=\([0-9]*\).*/\1/p')")
		check "uid" "$GUID" "$WUID"
		check "size" "$GSIZE" "$WSIZE"
		check "blocks" "$GBLK" "$WBLK"
		check "mtime" "$GMT" "$WMT"

		# the three new tier-0 fields, against debugfs's own reading.
		# A 256-byte inode has i_extra_isize 32, which reaches every
		# one of them; a 128-byte inode would have none, and the parser
		# reports 0 -- the same 0 ldiskfs_iget() leaves in the inode.
		WPROJ=$(echo "$S" | sed -n 's/.*Project: *\([0-9]*\).*/\1/p')
		WCR=$(echo "$S" | sed -n 's/^crtime: 0x\([0-9a-f]*\):.*/\1/p')
		WFLAGS=$(echo "$S" | sed -n 's/.*Flags: 0x\([0-9a-f]*\).*/\1/p')
		GPROJ=$(echo "$OUT" | sed -n 's/.*projid=\([0-9]*\).*/\1/p')
		GCR=$(printf %x "$(echo "$OUT" | sed -n 's/^btime=\([0-9]*\).*/\1/p')")
		GFLAGS=$(echo "$OUT" | sed -n 's/.*flags=0x\([0-9a-f]*\).*/\1/p')
		check "projid" "$GPROJ" "${WPROJ:-0}"
		check "crtime" "$GCR" "$WCR"
		# la_flags is i_flags masked to what Lustre shows users:
		# EXTENTS (0x80000) survives, and so do the sif-set bits on f1
		check "flags" "$GFLAGS" \
			"$(printf %x $(( 0x$WFLAGS & 0x709b5cfe )))"

		# osd_raw_xattr(): tier 1 from the same buffer
		case $n in
		5)	check "som inline" \
				"$(echo "$OUT" | sed -n 's/^xattr som rc=\([-0-9]*\).*/\1/p')" 0
			check "som bytes" \
				"$(echo "$OUT" | sed -n 's/^xattr som .*hex=//p')" "$SOM_HEX"
			if [ "$I" -ge 1024 ]; then
				# mkfs.lustre's inode size: the 80-byte LOV sits
				# beside the LMA and SOM with room to spare
				check "lov inline at $I" \
					"$(echo "$OUT" | sed -n 's/^xattr lov rc=\([-0-9]*\).*/\1/p')" 0
				check "lov bytes" \
					"$(echo "$OUT" | sed -n 's/^xattr lov .*hex=//p')" "$LOV_HEX"
			else
				# 256-byte inodes leave 96 bytes for xattrs, of
				# which the LMA entry takes 44: an 80-byte LOV
				# cannot fit and ext4 spills it.  This is design
				# §10.2's small-inode warning made concrete, and the
				# parser must say "not here", not find it anyway.
				check "lov spilled at $I: not claimed inline" \
					"$(echo "$OUT" | sed -n 's/^xattr lov rc=\([-0-9]*\).*/\1/p')" -61
				check "and the inode points at its block" \
					"$(echo "$OUT" | sed -n 's/.*file_acl=\([0-9]*\).*/\1/p' | \
					   awk '{print ($1 > 0) ? "yes" : "no"}')" yes
			fi
			;;
		3)	# trusted.big is 3000 bytes: external at both inode sizes,
			# so the in-inode lookup must say "not here" (-61) and the
			# inode must show a file_acl for the caller to follow
			check "external attr not claimed inline" \
				"$(echo "$OUT" | sed -n 's/^xattr big rc=\([-0-9]*\).*/\1/p')" -61
			check "and the inode points at its block" \
				"$(echo "$OUT" | sed -n 's/.*file_acl=\([0-9]*\).*/\1/p' | \
				   awk '{print ($1 > 0) ? "yes" : "no"}')" yes
			;;
		*)	check "absent attr is -ENODATA" \
				"$(echo "$OUT" | sed -n 's/^xattr som rc=\([-0-9]*\).*/\1/p')" -61
			;;
		esac
	done
done

[ "$FAIL" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
