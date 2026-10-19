#!/bin/bash
# 10-19 lab d (host, no root): B1 on a real image.  A 64M ext4 labelled
# lfst-OST0003 with four objects whose trusted.lma is written by debugfs:
# IDIF with OST index 0 (twice, one oid >= 2^32), IDIF with index 3, and a
# FID-on-OST.  Arms: old/ and new/ hold lfs + liblustreapi from the build
# tree at k1019-fork-1014 and fork-1014, and utils/scan_osd_ldiskfs.so.
# Controls: the same image relabelled lfst-OST0000 and lfst-MDT0003.
set -eu
S=$1; cd $S
rm -f ost3.img; truncate -s 64M ost3.img
mkfs.ext4 -q -F -I 512 -L lfst-OST0003 ost3.img
echo data > d.txt
python3 - <<'PY'
import struct
def lma(seq, oid, ver=0, compat=0x8): return struct.pack('<IIQII', compat, 0, seq, oid, ver)
open('a.lma','wb').write(lma(0x100000000, 0x1234))
open('b.lma','wb').write(lma(0x100000001, 0x5))
open('c.lma','wb').write(lma(0x100030000, 0x99))
open('d.lma','wb').write(lma(0x2c0000401, 0x10))
PY
for f in a b c d; do
	debugfs -w -R "write d.txt obj_$f" ost3.img >/dev/null 2>&1
	debugfs -w -R "ea_set -f $f.lma obj_$f trusted.lma" ost3.img 2>/dev/null
done
cp ost3.img ost0.img; tune2fs -L lfst-OST0000 ost0.img >/dev/null
cp ost3.img mdt3.img; tune2fs -L lfst-MDT0003 mdt3.img >/dev/null
for img in ost3 ost0 mdt3; do for n in old new; do
	echo "$img $n: $(LUSTRE=$S/$n LD_LIBRARY_PATH=$S/$n $S/$n/lfs find --device $S/$img.img --internal -printf '%LO\n' 2>&1 | sort | tr '\n' ' ')"
done; done
