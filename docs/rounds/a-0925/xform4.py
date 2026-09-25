#!/usr/bin/env python3
"""09-25 lreview of 68163: -ENOPKG from the ZFS backend gets its own
message, and a comment stated as a fact about the code.  Gated on the ZFS
backend being in the tree, so nothing below 68163 changes."""
import os, sys
T = sys.argv[1]
applied = skipped = 0
if not os.path.exists(os.path.join(T, "lustre/utils/libscan_zfs.c")):
    print("applied=0 skipped=gated"); sys.exit(0)
p = os.path.join(T, "lustre/utils/liblustreapi_scan_device.c")
s = open(p).read()
for old, new in (
    ("\tif (rc == -ENOPKG)\n"
     "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, rc,\n"
     "\t\t\t    \"%s: unsupported features; needs Lustre's e2fsprogs\",\n"
     "\t\t\t    device);\n",
     "\tif (rc == -ENOPKG && kind == SCAN_BACKEND_ZFS)\n"
     "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, rc,\n"
     "\t\t\t    \"%s: unsupported pool features; needs newer libzpool\",\n"
     "\t\t\t    device);\n"
     "\telse if (rc == -ENOPKG)\n"
     "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, rc,\n"
     "\t\t\t    \"%s: unsupported features; needs Lustre's e2fsprogs\",\n"
     "\t\t\t    device);\n"),
    (" * target answers for itself instead, -ENOPKG for an ldiskfs target this\n"
     " * libext2fs will not open and -EMEDIUMTYPE for a dataset holding no ZPL\n",
     " * target answers for itself instead, -ENOPKG for a target this libext2fs or\n"
     " * libzpool will not open and -EMEDIUMTYPE for a dataset holding no ZPL\n"),
    ("\t * stats as.  Routing by type alone sent a mount point or any other\n"
     "\t * directory to the ZFS backend, where the caller was told there was\n"
     "\t * no ZFS backend -- looking for a package rather than at the name\n"
     "\t * they typed -- or, on a ZFS build, -ENOENT for a path that plainly\n"
     "\t * exists, scan_zfs_open() having cut the name at its first slash.\n",
     "\t * stats as.  Routing by type alone would send a directory to the ZFS\n"
     "\t * backend, which answers -ENOTSUP or, as it cuts the name at its\n"
     "\t * first slash, -ENOENT for a path that exists.\n")):
    if old in s:
        s = s.replace(old, new); applied += 1
    else:
        skipped += 1
open(p, "w").write(s)
print(f"applied={applied} skipped={skipped}")
