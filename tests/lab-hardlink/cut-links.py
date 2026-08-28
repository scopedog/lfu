#!/usr/bin/env python3
"""The control arm for sanity 160ad.

Cuts the link enumeration out of find_since_pick(), leaving what the code
did before: the subtree test and the pre-filter against the one name
llapi_scan_fid() resolved, which is linkno 0 -- the name the file was
created under.  160ad must then fail on the search rooted at the other
directory, and on -name.
"""
import sys

root = sys.argv[1]
p = root + "/lustre/utils/liblustreapi_pfind.c"
s = open(p).read()

old = """	if (!find_since_hardlinked(rec) || !(rec->sr_valid & LLAPI_SCAN_FID))
		return false;
"""
new = """	return false;
	if (!find_since_hardlinked(rec) || !(rec->sr_valid & LLAPI_SCAN_FID))
		return false;
"""
assert old in s, "find_since_pick's enumeration guard not found"
open(p, "w").write(s.replace(old, new))
print("armed: control (no link enumeration)")
