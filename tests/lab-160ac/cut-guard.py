"""Remove the stale-anchor refusal, message and all, for the control arm.

Disabling only the condition ("if (0 && ...)") leaves the error string in the
library, and then nothing distinguishes an installed control build from an
installed post one -- which matters, because the obvious check, md5summing
/bin/lfs, never changes: the guard is in liblustreapi.so, not in the binary.
"""
import sys

p = sys.argv[1]
s = open(p).read()
old = '''\t\t\tif (sc.sc_startrec != 0 && oldest > sc.sc_startrec) {
\t\t\t\tllapi_error(LLAPI_MSG_ERROR |
\t\t\t\t\t    LLAPI_MSG_NO_ERRNO, -ESTALE,
\t\t\t\t\t    "'%s' has purged past the cookie: it starts at %llu and '%s' says %llu, so records in between are gone",
\t\t\t\t\t    mdtname, (unsigned long long)oldest,
\t\t\t\t\t    param->fp_since_cookie,
\t\t\t\t\t    (unsigned long long)sc.sc_startrec);
\t\t\t\trc = -ESTALE;
\t\t\t\tbreak;
\t\t\t}
'''
if old not in s:
    sys.exit("CONTROL PATCH DID NOT MATCH -- the guard block has changed")
open(p, 'w').write(s.replace(old, "", 1))
print("control: stale-anchor refusal removed")
