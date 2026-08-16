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

cp "$HERE/bpval.c" .
gcc -O1 -o bpval bpval.c

# --- the LMA to plant: compat 0, incompat 0, FID [0x200000401:0x1a2b3c4d:0x0]
python3 -c "
import struct,sys
sys.stdout.buffer.write(struct.pack('<IIQII', 0, 0, 0x200000401, 0x1a2b3c4d, 0))" > lma.bin
head -c 300000 /dev/urandom > payload
head -c 3000 /dev/zero | tr '\0' 'x' > big.bin

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
	mke2fs -q -t ext4 -I $I -b 4096 -F -O ^has_journal $IMG
	for n in 1 2 3 4; do debugfs -w -R "write payload f$n" $IMG >/dev/null 2>&1; done
	debugfs -w -R "ea_set -f lma.bin f1 trusted.lma"  $IMG >/dev/null 2>&1
	# f2: nothing
	debugfs -w -R "ea_set -f big.bin f3 trusted.big"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f lma.bin f3 trusted.lma"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set f4 trusted.aaa hello"       $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set -f lma.bin f4 trusted.lma"  $IMG >/dev/null 2>&1
	debugfs -w -R "ea_set f4 user.zzz world"          $IMG >/dev/null 2>&1
	# non-default identity and mode on f1, to exercise the high halves
	debugfs -w -R "sif f1 uid 65123" $IMG >/dev/null 2>&1
	debugfs -w -R "sif f1 gid 4294967295" $IMG >/dev/null 2>&1

	ITAB=$(dumpe2fs $IMG 2>/dev/null | grep -m1 "Inode table at" | sed 's/.*at \([0-9]*\).*/\1/')
	echo "== inode size $I (inode table at block $ITAB)"

	for n in 1 2 3 4; do
		INO=$(debugfs -R "stat f$n" $IMG 2>/dev/null | head -1 |
		      sed 's/Inode: \([0-9]*\).*/\1/')
		OUT=$(./bpval $IMG "$INO" "$ITAB" 32768 "$I" 1)
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
	done
done

[ "$FAIL" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
