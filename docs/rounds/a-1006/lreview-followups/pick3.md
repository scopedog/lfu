# 4244d46ec4 — LU-20650 lfs: find --since, pick before the gather

- **Commit:** `4244d46ec46d` (4244d46ec4, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 2.0M tokens, $1.38, 2m13s

## Overall assessment

Looks good. One optional comment nit inline for whenever the patch is next refreshed; no need to re-spin for it.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 5659)

(minor) If the patch is refreshed: the double walk isn't limited to a file whose first name is outside the subtree. A file whose first name is inside it but fails -name walks its links in both places too, because find_since_pick() falls through to the fid2path loop whenever find_prefilter() rejects the first name. That is the "--since -name g" case in sanity 160Ad. Conversely, a first name outside the subtree only costs the second walk when some link is accepted. Something like "One whose first name the pick rejects, but another name passes, walks them here and again in find_since_rec_cb()" would cover both. The same sentence is in the commit message.
