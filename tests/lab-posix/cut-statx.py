#!/usr/bin/env python3
# NOSTATX arm: put the lstat(2) fallback back.
#
# LU-20665 asks the kernel with statx(2) for an object the MDT ioctl cannot
# answer for, so a birth time and the attribute flags arrive where the
# filesystem has them.  With lstat back, LLAPI_SCAN_BTIME is clear whatever the
# filesystem knows and "lfs find -btime" matches nothing -- which sanity 157d
# must catch on a filesystem that reports a birth time.
#
# Cuts the #ifdef rather than the body: the body has already been edited once
# since this arm was written, and an arm that stops matching is an arm that
# quietly stops running.  There are two HAVE_STATX blocks in the file, so this
# finds the one belonging to the ENOTTY fallback by its error string.
import sys

p = sys.argv[1]
s = open(p).read()

mark = '"error: %s: statx failed for %s"'
if mark not in s:
    sys.exit("NOSTATX CUT DID NOT MATCH -- no statx in the ENOTTY fallback")
i = s.rindex("#ifdef HAVE_STATX", 0, s.index(mark))
s = s[:i] + "#if 0	/* NOSTATX ARM */" + s[i + len("#ifdef HAVE_STATX"):]
open(p, 'w').write(s)
print("nostatx arm: the lstat fallback is back")
