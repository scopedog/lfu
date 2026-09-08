#!/usr/bin/env python3
"""Lift scan_lmv_to_user() out of the tree for lmv_stale.c.  See lift.py."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lift import lift
T, out = sys.argv[1], sys.argv[2]
s = lift(T + "/lustre/utils/liblustreapi_scan_device.c", "scan_lmv_to_user")
open(out, "w").write(s.replace("static __u32 scan_lmv_to_user", "__u32 scan_lmv_to_user", 1))
print("lifted %d bytes" % len(s))
