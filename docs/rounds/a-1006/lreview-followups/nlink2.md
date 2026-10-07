# 32e7af285c — LU-20650 llapi: pass FID and nlink to llapi_scan_fid() filter

- **Commit:** `32e7af285ceb` (32e7af285c, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 1.6M tokens, $1.31, 2m45s

## Overall assessment

Looks good. Two optional items inline for the next refresh; neither needs a re-spin on its own.

## Findings

### 1. `Documentation/man3/llapi_scan_fid.3` (line 113)

(minor) This sentence is missing a conjunction. As written it reads as "fid itself, with LLAPI_SCAN_FID for anything but a directory", as if the FID were the part left out for directories. Perhaps:

    It also gets fid itself, with LLAPI_SCAN_FID set in lfsr_valid,
    and, for anything but a directory, the link count in
    lfsr_stx.stx_nlink with STATX_NLINK set in stx_mask.

The page also doesn't say that a filter should test STATX_NLINK before trusting stx_nlink. The bit is left clear for a directory, when statx() does not report the count, and when the count read back is 0 (for example, a file unlinked after fid2path resolved it). A filter that skips the fid2path lookup on "stx_nlink == 1" needs to know it may get neither.

### 2. `lustre/tests/llapi_scan_test.c` (line 945)

(suggestion) The commit message says the link count is passed for hardlinked files, but this only checks a file with one link. A count stuck at 1, or one taken from the wrong place, would still pass. Consider link()ing a second name to a scratch file and checking that the filter sees stx_nlink == 2.
