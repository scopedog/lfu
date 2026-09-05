# cd2c36e8f1 — LU-20603 llapi: namespace scanner API

- **Commit:** `cd2c36e8f14c` (cd2c36e8f1, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 9.6M tokens, $8.97, 18m08s

## Overall assessment

Mostly good, two comments inline.

## Findings

### 1. `include/lustre/lustreapi.h` (line 722)

(minor) Is this true when readdir(3) does not fill in d_type?

llapi_semantic_traverse() resolves the type itself before it calls the cb_init hook:

    if (dent->d_type == DT_UNKNOWN) {
        rc = get_lmd_info_fd(path, d, -1, param->fp_lmd,
                             param->fp_lum_size, GET_LMD_INFO);

That runs ahead of llapi_scan_cb_init(), so ahead of sp_filter and ahead of the `want & LLAPI_SCAN_MDT_MASK` test in scan_rec_gather(). On a filesystem whose directory entries carry no type -- ext4 without the filetype feature, XFS with ftype=0, and the non-Lustre trees the page's "A target that is not Lustre" section documents -- a name-only scan still pays one IOC_MDC_GETFILEINFO/lstat per object.

The same case makes "As sp_filter it is called before any I/O on the object" a few lines up not hold there either. Worth qualifying both, since the cheap name search is the reason the demand mask exists.

### 2. `include/lustre/lustreapi.h` (line 657)

(style) This isn't a bug, but carrying forward the alignment point from the previous revision, since it is unchanged: sr_projid/sr_mdt_index/sr_lmvsize are three consecutive __u32, so the compiler inserts four bytes of implicit padding before sr_lmm.

Compiled on x86_64 the record is 352 bytes with sr_lmvsize ending at 316 and sr_lmm starting at 320. Since sr_size is the record's forward-compatibility contract, an explicit __u32 sr_padding there would make the hole visible and reusable rather than leaving it to the compiler.
