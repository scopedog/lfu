# AI on 68159 PS36:
# fa712d02: Fixes: lines go just above the trailers.
# 1e2474be: two passages describe earlier patchsets, not the code.
SUBJ = "LU-20611 llapi: run find over a device scan"
MSG = [
("""it would otherwise be decided on a stx_size the scan never reported.
The fix is Artem Blagodarenko's.

Fixes: 6b8e97b76c47 ("LU-10378 utils: add formatted printf to lfs find")
Fixes: 186b97e68abb ("LU-11971 utils: Send file creation time to clients")

""",
"""it would otherwise be decided on a stx_size the scan never reported.

"""),
("""llapi_find_device() clears lfsp_got.  scan_param_copyin() copies the
caller's block whole, so the caller's pointer came through and was
answered with find's own demand mask -- a mask for a question the
caller never asked.

Signed-off-by:""",
"""llapi_find_device() leaves lfsp_got zero: filled, it would report
find's own demand mask, not the caller's.

Fixes: 6b8e97b76c47 ("LU-10378 utils: add formatted printf to lfs find")
Fixes: 186b97e68abb ("LU-11971 utils: Send file creation time to clients")
Signed-off-by:"""),
]
def msgfn(msg, subj):
    if subj == SUBJ:
        for o, n in MSG:
            assert o in msg, 'msg anchor: ' + o[:40]
            msg = msg.replace(o, n)
    return msg
def fn(path, s, subj):
    return s
