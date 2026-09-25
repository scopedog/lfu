#!/usr/bin/env python3
"""09-25 lreview of 68156, finding 1: the walk refuses LLAPI_SCAN_F_INTERNAL.

Only where the flag exists, so 68094 (final at PS26) is never touched.
"""
import os, sys
T = sys.argv[1]
h = open(os.path.join(T, "include/lustre/lustreapi.h")).read()
p = os.path.join(T, "Documentation/man3/llapi_scan_namespace.3")
old = "sets a bit this library does not define, or\n"
new = ("sets a bit this library does not define or that only\n"
       ".BR llapi_scan_device (3)\n"
       "acts on, such as\n"
       ".BR LLAPI_SCAN_F_INTERNAL ,\n"
       "or\n")
s = open(p).read() if os.path.exists(p) else ""
if "define LLAPI_SCAN_F_INTERNAL" in h and old in s:
    open(p, "w").write(s.replace(old, new))
    print("applied=1")
else:
    print("applied=0")
