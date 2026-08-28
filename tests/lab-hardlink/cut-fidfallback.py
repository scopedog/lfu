#!/usr/bin/env python3
"""The control arm for 160ab's unlinked-object case.

Cuts the FID fallback back out of find_changelog_rec_cb(), leaving what
find_decide() does for a target scan: an object whose FID no longer resolves
to a pathname is counted as having none rather than named by its FID.  160ab
must then fail on the object it unlinked -- the one thing --changelog can
report that --since cannot.
"""
import sys

root = sys.argv[1]
p = root + "/lustre/utils/liblustreapi_pfind.c"
s = open(p).read()

old = """	/* an object unlinked since its event is in this answer, by FID */
	fc.fc_fid_when_lost = true;
"""
new = """	fc.fc_fid_when_lost = false;
"""
assert old in s, "fc_fid_when_lost assignment not found"
open(p, "w").write(s.replace(old, new))
print("armed: nofid (no FID fallback under --changelog)")
