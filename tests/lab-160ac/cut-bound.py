#!/usr/bin/env python3
# NOBOUND arm: put back the bound test that let a negative MDT index through.
#
# "%x" accepts a sign, so a cookie line of "<fsname>-MDT-1 42" parses to
# 0xffffffff; compared as (int) that is -1, which passes ">= nstarts", and the
# store then lands ~32GB past the anchor array.  160ac feeds exactly that line,
# so this arm must die or corrupt where the fixed one ignores it.
import sys

p = sys.argv[1]
s = open(p).read()
old = '''		num = name + fslen + strlen("-MDT");
		if (*num == '-' || *num == '+')
			continue;
		if (sscanf(num, "%4x", &mdt) != 1)
			continue;
		if (mdt >= (unsigned int)nstarts)
			continue;
'''
new = '''		(void)num;	/* NOBOUND ARM */
		if (sscanf(name + fslen, "-MDT%04x", &mdt) != 1)
			continue;
		if ((int)mdt >= nstarts)
			continue;
'''
if old not in s:
    sys.exit("NOBOUND CUT DID NOT MATCH -- find_cookie_read() has changed")
open(p, 'w').write(s.replace(old, new))
print("nobound arm: the signed bound test is back")
