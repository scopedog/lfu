O288 = """directory is named through its master directory. A shard itself is
not in the namespace and is not reported, and llapi_scan_rec_path()
answers -ENOENT for one. Below an encrypted directory the linkea holds
the name the client encrypted, so such an object is counted as having
no pathname rather than printed as ciphertext. The pre-pass asks for
LLAPI_SCAN_LMV, and every search asks for LLAPI_SCAN_LMV_SHARD, which
also reads trusted.lmv.
llapi_scan_namespace.3 has a section on shards.
"""
N288 = """directory is named through its master directory. A shard itself is
not in the namespace, and llapi_scan_rec_path() answers -ENOENT for
one. Below an encrypted directory the linkea holds the name the client
encrypted, so such an object is counted as having no pathname rather
than printed as ciphertext. The pre-pass asks for LLAPI_SCAN_LMV,
which is what tells a shard from a directory.
"""
P159 = """A striped directory has a shard on each MDT it is striped over. A
shard has a normal FID, an LMA and a linkea of its own, so a search
over an MDT would report it as a directory, once per MDT. The device
gather marks one with LLAPI_SCAN_LMV_SHARD, from its LMV_MAGIC_STRIPE
trusted.lmv, and find_device_cb() skips it: the master answers for the
directory, once, as a walk does. llapi_scan_namespace.3 documents the
flag.
"""
def fn(path, s, subj):
    return s
def msgfn(m, subj):
    if subj.startswith("LU-20637 llapi: name a device scan's objects"):
        assert m.count(O288) == 1
        return m.replace(O288, N288)
    if subj.startswith('LU-20611 llapi: run find over a device scan'):
        lines = m.rstrip('\n').split('\n')
        i = next(k for k, l in enumerate(lines)
                 if l.startswith(('Test-Parameters:', 'Signed-off-by:')))
        body = '\n'.join(lines[:i]).rstrip('\n')
        return body + '\n\n' + P159 + '\n' + '\n'.join(lines[i:]) + '\n'
    return m
