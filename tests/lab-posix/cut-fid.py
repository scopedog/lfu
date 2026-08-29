#!/usr/bin/env python3
# NOFID arm: put back the FID a stat never answered for.
#
# convert_lmd_statx() fills lmd_stx from a stat and leaves lmd_fid alone.  The
# walk wrote the object's NAME into that buffer for the ioctl that then failed
# with ENOTTY, and fid_is_sane() reads those bytes as an IGIF -- so the record
# came back with LLAPI_SCAN_FID set and a FID built out of the filename.
# llapi_scan_test's POSIX case must fail against this arm.
import sys

p = sys.argv[1]
s = open(p).read()
old = '''	/*
	 * Neither caller has a FID to give: a stat answers for an object the
	 * ioctl could not, and the bytes at lmd_fid are the name the caller
	 * wrote there for that ioctl, or the V1 lmd_st that sat where a FID
	 * sits now.  Either reads as a plausible IGIF.
	 */
	memset(&lmd_v2->lmd_fid, 0, sizeof(lmd_v2->lmd_fid));
'''
new = '''	/* NOFID ARM: the clear is cut out */
'''
if old not in s:
    sys.exit("NOFID CUT DID NOT MATCH -- convert_lmd_statx() has changed")
open(p, 'w').write(s.replace(old, new))
print("nofid arm: the stat answer keeps whatever was at lmd_fid")
