#!/usr/bin/env python3
# NOSTATX arm: put the lstat(2) fallback back.
#
# LU-20665 asks the kernel with statx(2) for an object the MDT ioctl cannot
# answer for, so a birth time and the attribute flags arrive where the
# filesystem has them.  With lstat back, LLAPI_SCAN_BTIME is clear whatever the
# filesystem knows and "lfs find -btime" matches nothing -- which sanity 157d
# must catch on a filesystem that reports a birth time.
import sys

p = sys.argv[1]
s = open(p).read()
old = '''#ifdef HAVE_STATX
			ret = statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW,
				    STATX_BASIC_STATS | STATX_BTIME,
				    &lmd->lmd_stx);
			if (ret) {
				ret = -errno;
				llapi_error(LLAPI_MSG_ERROR, ret,
					    "error: %s: statx failed for %s",
					    __func__, path);
			}
			lmd_stx_finish(lmd, true);
#else
'''
new = '''#if 0	/* NOSTATX ARM */
#else
'''
if old not in s:
    sys.exit("NOSTATX CUT DID NOT MATCH -- the ENOTTY branch has changed")
open(p, 'w').write(s.replace(old, new))
print("nostatx arm: the lstat fallback is back")
