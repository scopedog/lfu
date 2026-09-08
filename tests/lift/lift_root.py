#!/usr/bin/env python3
"""Lift scan_classify() out of the tree for root_fid.c.  See lift.py."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lift import lift
T, out = sys.argv[1], sys.argv[2]
s = lift(T + "/lustre/utils/liblustreapi_scan_device.c", "scan_classify")
open(out, "w").write(s.replace("static enum llapi_scan_class scan_classify",
                               "enum llapi_scan_class scan_classify", 1))
print("lifted %d bytes" % len(s))
