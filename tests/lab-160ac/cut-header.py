#!/usr/bin/env python3
# NOHEADER arm: stop refusing a cookie written for another filesystem.
#
# The header line then falls through to the per-line parse, which ignores it
# like any other comment, so every anchor reads as 0: this filesystem rescans
# its whole changelog and the rewrite drops the other filesystem's lines.  Both
# silently, which is what 160ac's last case is for.
import sys

p = sys.argv[1]
s = open(p).read()
old = '''			if (strcmp(name, fsname) == 0)
				continue;
			llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
				    -EINVAL,
				    "'%s' is a cookie for '%s', not for '%s'",
				    file, name, fsname);
			fclose(fp);
			return -EINVAL;
'''
new = '''			continue;	/* NOHEADER ARM */
'''
if old not in s:
    sys.exit("NOHEADER CUT DID NOT MATCH -- find_cookie_read() has changed")
open(p, 'w').write(s.replace(old, new))
print("noheader arm: a foreign cookie is accepted again")
