# 0a175c4191 — LU-20650 lfs: find --since, pick before the gather

- **Commit:** `0a175c419162` (0a175c4191, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 1.8M tokens, $1.33, 2m29s

## Overall assessment

Looks good. The filter only rejects what find_since_rec_cb() would reject, so the printed set does not change. Two optional points are inline; neither needs a re-spin on its own.

## Findings

### 1. `/COMMIT_MSG` (line 24)

(minor) The printed answer is the same, but the warnings and exit status can change. Before this patch, an object outside the subtree whose gather failed was still counted in find_since_cand_cb(): -ESTALE went to fss_gone ("... no longer exist"), and any other error such as -EACCES from the parent open under root squash went to fss_dropped/fss_scan_rc ("... could not be read" plus a non-zero return). Now the filter skips that object before the gather, so nothing is counted. This brings --since closer to a walk of the subtree, which never sees those objects. If the patch is refreshed, it may be worth saying so here, so the change in warnings is not a surprise.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5662)

(suggestion) llapi_scan_fid() already has the FID it was asked about, but it hands lfsp_filter a record from scan_rec_dirent() without lfsr_fid. That is why the FID goes through fss_pre_fid, which still points at the candidate record after llapi_scan_fid() returns. llapi_scan_fid() is not landed yet (34bea417d0, earlier in this series). Could it set rec.lfsr_fid and LLAPI_SCAN_FID before calling the filter? That would remove the side channel and give every lfsp_filter user the FID. If not, consider clearing fss_pre_fid after the call.
