# f229155db8 — LU-20650 llapi: llapi_scan_fid(), FID and nlink to the filter

- **Commit:** `f229155db89e` (f229155db8, local review — not tied to a Gerrit change)
- **Review:** 4 finding(s), severity **low**
- **Run:** opus, 1.6M tokens, $1.31, 2m00s

## Overall assessment

Looks good; the code change is correct and test 17 covers it. A few optional documentation points inline for whenever the patch is next refreshed. No need to re-spin for them.

## Findings

### 1. `/COMMIT_MSG` (line 7)

(style) This isn't a bug, but the summary is a noun phrase rather than an imperative. If the patch is refreshed, something like "llapi: pass FID and nlink to llapi_scan_fid() filter" would read more like the rest of the log.

### 2. `Documentation/man3/llapi_scan_fid.3` (line 152)

(minor) Is this paragraph still accurate? The filter now gets the FID and stx_nlink precisely so that a subtree filter can check a hardlinked file's other names, rather than taking or leaving it by the MDT's link order. That order still decides which path is in lfsr_path and where the gather runs, but a filter that uses the new fields is no longer bound by it. If the patch is refreshed, it may be worth saying so here.

### 3. `Documentation/man3/llapi_scan_fid.3` (line 116)

(minor) For a directory, stx_nlink is 2 plus the number of subdirectories, not a count of names; a directory always has exactly one. A filter that follows this text, treating nlink > 1 as "has other names", would call fid2path for every directory with subdirectories, which is the per-object cost this change is meant to avoid. If the patch is refreshed, maybe say the link count only means this for non-directories, or leave STATX_NLINK out of the filter's record when S_ISDIR(mode).

### 4. `lustre/utils/liblustreapi_scan.c` (line 727)

(minor) Same as the man page: since the filter now gets the FID and link count to look at the other names, this kernel-doc paragraph about a subtree filter taking or leaving a multiply-linked file by link order looks stale.
