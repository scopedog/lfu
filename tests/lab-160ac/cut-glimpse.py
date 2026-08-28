"""Disable the --resolve glimpse for the noglimpse control arm.

The condition is neutered rather than the call deleted: removing the call
leaves find_cl_glimpse() and find_cl_needs_glimpse() defined and unreferenced,
and the tree builds with -Werror, so the arm fails to compile instead of
failing the test.

Without the glimpse the lookup returns the MDT's lazy size, -size is
undecidable for every object, and lfs find exits 0 having reported nothing --
the state 160ab's old assertion could not tell from success.
"""
import sys

p = sys.argv[1]
s = open(p).read()
old = '''	if (find_cl_needs_glimpse(m->fcm_st->fss_param, &rec))'''
new = '''	if (0 /* NOGLIMPSE ARM */ && find_cl_needs_glimpse(m->fcm_st->fss_param, &rec))'''
if old not in s:
    sys.exit("NOGLIMPSE PATCH DID NOT MATCH")
open(p, 'w').write(s.replace(old, new, 1))
print("control: --resolve glimpse disabled")
