#!/usr/bin/env python3
"""09-25 follow-up to xform.py: wrap the two lines checkpatch flagged."""
import os, sys
T = sys.argv[1]
applied = skipped = 0
for path, old, new in (
    ("lustre/utils/libscan_ldiskfs.c",
     "\t\t\tobj->so_rdev = (((old >> 8) & 0xff) << 20) | (old & 0xff);\n",
     "\t\t\tobj->so_rdev = (((old >> 8) & 0xff) << 20) |\n"
     "\t\t\t\t       (old & 0xff);\n"),
    ("lustre/utils/lustreapi_scan_backend.h",
     "\t__u32\tso_rdev;\t\t/* la_rdev of a device node, as the OSD has it */\n",
     "\t__u32\tso_rdev;\t\t/* la_rdev of a device node */\n")):
    p = os.path.join(T, path)
    s = open(p).read() if os.path.exists(p) else ""
    if old in s:
        open(p, "w").write(s.replace(old, new)); applied += 1
    else:
        skipped += 1
print(f"applied={applied} skipped={skipped}")
