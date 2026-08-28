#!/usr/bin/env python3
"""Arms for the ss_seen accounting control.

inject: make every 7th object take the SKIP_XATTR path, which the backend
        raises AFTER the pre-filter has already counted the object.  A clean
        device produces no torn reads on its own, so without this the arm
        that is wrong and the arm that is right agree.
control: inject, plus scan_sink_skip() counting ss_seen for every reason --
        the code as it was before the fix.
"""
import sys, re

arm = sys.argv[1]
root = sys.argv[2]

p = root + "/lustre/utils/libscan_ldiskfs.c"
s = open(p).read()
old = """		if (scan_read_xattrs(wk, ino, sink->ss_want_xattr,
				     &obj) < 0) {"""
new = """		if ((ino % 7) == 0 ||
		    scan_read_xattrs(wk, ino, sink->ss_want_xattr,
				     &obj) < 0) {"""
assert old in s, "xattr call not found"
open(p, "w").write(s.replace(old, new))

if arm == "control":
    p = root + "/lustre/utils/liblustreapi_scan_device.c"
    s = open(p).read()
    old = """	if (why != LLAPI_SCAN_SKIP_XATTR)
		w->sw_stats.ss_seen++;"""
    new = """	(void)why;
	w->sw_stats.ss_seen++;"""
    assert old in s, "skip guard not found"
    open(p, "w").write(s.replace(old, new))

print("armed:", arm)
