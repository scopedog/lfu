#!/usr/bin/python3
# Make an IGIF-root MDT image from a normal one: ROOT's LMA becomes the IGIF
# of its inode, and every linkea naming LU_ROOT_FID as parent names it instead.
import re, struct, subprocess, sys, os, shutil
src, dst = sys.argv[1], sys.argv[2]
shutil.copyfile(src, dst)
def dbg(cmd, w=False):
    r = subprocess.run(["debugfs"] + (["-w"] if w else ["-c"]) + ["-R", cmd, dst],
                       capture_output=True, text=True)
    return r.stdout + r.stderr
st = dbg("stat /ROOT")
ino = int(re.search(r"Inode: (\d+)", st).group(1))
gen = int(re.search(r"Generation: (\d+)", st).group(1))
root_be = struct.pack(">QII", 0x200000007, 1, 0)
igif_be = struct.pack(">QII", ino, gen, 0)
tmp = dst + ".xa"
dbg("ea_get -f %s /ROOT trusted.lma" % tmp)
lma = bytearray(open(tmp, "rb").read())
assert struct.unpack_from("<QII", lma, 8) == (0x200000007, 1, 0), lma
struct.pack_into("<QII", lma, 8, ino, gen, 0)
open(tmp, "wb").write(lma); dbg("ea_set -f %s /ROOT trusted.lma" % tmp, True)
names = [l.split()[-1] for l in dbg("ls -l /ROOT").splitlines()
         if l.strip() and l.split()[-1] not in (".", "..")]
for n in names:
    os.remove(tmp) if os.path.exists(tmp) else None
    dbg("ea_get -f %s /ROOT/%s trusted.link" % (tmp, n))
    if not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        print("  %s: no linkea" % n); continue
    b = open(tmp, "rb").read(); c = b.count(root_be)
    open(tmp, "wb").write(b.replace(root_be, igif_be))
    dbg("ea_set -f %s /ROOT/%s trusted.link" % (tmp, n), True)
    print("  %s: %d parent(s) rewritten" % (n, c))
os.remove(tmp)
print("IGIF root [0x%x:0x%x:0x0]" % (ino, gen))
print(dbg("ea_list /ROOT"))
print(dbg("ea_list /ROOT/.lustre"))
