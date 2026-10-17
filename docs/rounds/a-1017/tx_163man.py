# AI on 68163 PS36 7bf7ed99: root gets -ENOENT, not -EACCES, for an
# unreadable device under the search path (scan_zfs_import()).
R = {
'Documentation/man3/llapi_scan_device.3': [(
"""also the answer when the pool was not found and some device under the
search path could not be read.
""",
"""also the answer when the pool was not found, some device under the
search path could not be read, and the caller is not root.
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
