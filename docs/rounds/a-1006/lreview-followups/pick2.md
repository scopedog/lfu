# 7f89ccd7f4 — LU-20650 lfs: find --since, pick before the gather

- **Commit:** `7f89ccd7f49f` (7f89ccd7f4, local review — not tied to a Gerrit change)
- **Review:** 4 finding(s), severity **low**
- **Run:** opus, 1.2M tokens, $1.10, 1m45s

## Overall assessment

Mostly good. The answer looks unchanged, but the commit message overstates how much the warnings change, and directories rejected by the filter pay an extra fid2path. Comments inline.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 5658)

(minor) Is this true for directories? llapi_scan_fid() gives the filter record only STATX_TYPE | STATX_NLINK, but find_since_hardlinked() tests STATX_MODE before excluding a directory:

    if ((rec->lfsr_stx.stx_mask & STATX_MODE) &&
        S_ISDIR(rec->lfsr_stx.stx_mode))
            return false;

So in the filter, every directory with nlink > 1 counts as hardlinked. If find_since_under() or -name/-type rejects it, find_since_pick() goes on to one more llapi_fid2path_at() before linkno == prev stops the loop. find_since_rec_cb() gets the MDT's statx, where STATX_MODE is set, so it never does this. The answer stays the same, but each rejected directory costs an extra MDT round trip. Should find_since_hardlinked() test STATX_TYPE, which both records carry?

### 2. `lustre/utils/liblustreapi_pfind.c` (line 6174)

(suggestion) This isn't a bug, but for a hardlinked file whose first name is outside the subtree, the filter walks its links with fid2path and then throws the result away. find_since_rec_cb() then repeats the same walk on the gathered record, so such a file now costs twice the fid2path calls it did before. Probably rare enough not to matter, but it may be worth a sentence in the comment above find_since_pre_cb().

### 3. `/COMMIT_MSG` (line 25)

(minor) This overstates the change. In llapi_scan_fid(), both the fid2path lookup and the statx() run before lfsp_filter. So an unlinked object outside the subtree still fails fid2path with -ENOENT and is still counted in fss_gone. An object under a directory the caller cannot search still fails statx() with -EACCES and is still dropped, which sets the exit status. Only failures from the gather itself are avoided now: the openat() of an unreadable parent, and -ESTALE/-ENOENT races after the statx. The comment in find_since_cand_cb() makes this same statx -EACCES point. Could this paragraph be narrowed to match, and "A walk of the subtree never meets such an object either" not imply the warnings now match a walk?

### 4. `/COMMIT_MSG` (line 19)

(minor) Same point as the inline comment on find_since_pre_cb(). In the filter, a directory with nlink > 1 also looks up its names, because the filter record has no STATX_MODE. So "exactly as find_since_rec_cb() does" doesn't quite hold yet.
