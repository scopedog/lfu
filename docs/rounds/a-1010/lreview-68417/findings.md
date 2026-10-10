# HEAD — LU-20650 lfs: add find --since, from the changelog

- **Commit:** `d4fb6de444e6` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 6.0M tokens, $4.15, 9m39s

## Overall assessment

Looks good. Three optional nits inline for whenever the patch is next refreshed; none of them is a reason to re-spin.

## Findings

### 1. `/COMMIT_MSG` (line 59)

(minor) The body covers copying the MDT index into the caller's find_param, but not find_rec_dir_stub(), which this patch also adds: for an unstriped directory it forges an LMV_MAGIC_V1 header carrying that index, so %Li and %Lo have something to print. If the patch is refreshed, could the body name it here, next to the --mdt sentence it depends on?

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5054)

(style) This isn't a bug, but this one-line comment describes find_since_cand_cb(), and find_since_failed_under() has since been placed between the two, so it now reads as a second header for that helper. If the patch is refreshed, it could move down to sit directly above find_since_cand_cb().

### 3. `lustre/utils/liblustreapi_pfind.c` (line 5157)

(style) This isn't a bug, but the second paragraph describes what an earlier version of this function did ("returning rc here ended the whole run") rather than what the code below does, and the whole block sits above the find_since_failed_under() test instead of the `!fp_stop_on_error` branch it explains. If the patch is refreshed, consider keeping only the first paragraph and placing it on that branch; the history is better left to the commit message.
