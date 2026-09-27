# HEAD — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `144a102640b5` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 8.4M tokens, $4.19, 7m32s

## Overall assessment

Looks good; one optional point inline for whenever the patch is next refreshed -- no need to re-spin for it.

## Findings

### 1. `lustre/utils/liblustreapi_scan_changelog.c` (line 370)

(minor) Should a regular file's ctime (and atime) follow the same rule as its mtime here? mtime is left out when no glimpse ran, because the OSTs hold a newer one. But ll_merge_attr_nolock() merges cat_ctime and cat_atime from the OST objects exactly as it does cat_mtime, and with need_glimpse false ll_getattr_dentry() skips that merge for a regular file.

So sc_want = LLAPI_SCAN_CTIME with _RESOLVE does not glimpse (the test just above only looks at SIZE/BLOCKS/MTIME). For a file another client is still writing, it then gets the MDT's older ctime, and STATX_CTIME claims it is exact.

llite's own statx(STATX_CTIME) behaves the same way, so this may be deliberate. If so, the page and the commit message, which say only size and mtime need the glimpse, could say so. Otherwise, adding LLAPI_SCAN_CTIME (and ATIME) to the glimpse test, or leaving them out of stx_mask when !glimpse for S_ISREG, would keep the rule the same for all three times.
