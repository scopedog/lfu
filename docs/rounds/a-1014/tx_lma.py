# adilger on 68156 PS30 (llapi_scan_device.3): a 1.8 filesystem is not a
# practical case; a link or LMA lost to xattr corruption is.
R = {
'Documentation/man3/llapi_scan_device.3': [(
"""A file from before linkEA (Lustre 1.8, with an IGIF) that LFSCK has not yet
given one is counted here too, having nothing on the target to say it is
reachable.
On an MDT upgraded from 1.8 with no namespace LFSCK run, those are user files,
and a default scan holds them back.
""",
"""So is a user file whose
.B trusted.link
was lost, to xattr corruption say: nothing on the target says it is reachable,
so a default scan holds it back until LFSCK restores the link.
"""), (
""".BR trusted.lma ,
so with no FID of its own recorded.
On MDT0000,
""",
""".BR trusted.lma ,
so with no FID of its own recorded.
Every object has had one since Lustre 2.4, so on a filesystem formatted since
then this is an object that lost it, to xattr corruption say, and LFSCK can
rebuild it.
On MDT0000,
""")],
'lustre/utils/liblustreapi_scan_device.c': [(
""" * is the target's own.  So is a file from before linkEA (1.8, an IGIF) that
 * LFSCK has not given one yet: it is reachable, but nothing here says so.
""",
""" * is the target's own.  So is a user file whose trusted.link was lost: it is
 * reachable, but nothing here says so.
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
