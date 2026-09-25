#!/usr/bin/env python3
"""68163's message: state reasons as facts about the code (lreview 09-25)."""
import sys
m = sys.stdin.read()
if "Change-Id: I97a6d8815924b2671c818152f42d66cc580a609d" in m:
    for old, new in (
        ("a pool listed there\nwas opened directly, before those checks, and a pool the kernel held\n"
         "answered EREMOTEIO instead of EBUSY.",
         "a pool listed there\nwould be opened directly, before those checks, and a pool the kernel\n"
         "holds would answer EREMOTEIO instead of EBUSY."),
        ("scan.  sanity 131d is what noticed: it reads errno through rwv, which",
         "scan.  sanity 131d shows this: it reads errno through rwv, which"),
        ("says why.  A lab build is what caught it: nm still read \"w\n"
         "scan_zfs_open\" and the binary held no libzpool symbol at all.  So the\n"
         "program names one symbol undefined up front, -Wl,-u,scan_zfs_open,\n",
         "says why: nm reads \"w scan_zfs_open\" and the binary holds no\n"
         "libzpool symbol at all.  So the program names one symbol undefined\n"
         "up front, -Wl,-u,scan_zfs_open,\n"),
        ("sanity on every change -- which is how 131d found this to begin with.\n",
         "sanity on every change.\n")):
        if old not in m and new not in m:
            sys.exit("msg4: anchor missing: " + old[:50])
        m = m.replace(old, new)
sys.stdout.write(m)
