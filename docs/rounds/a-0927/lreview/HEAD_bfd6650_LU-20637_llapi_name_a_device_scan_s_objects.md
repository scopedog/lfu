# HEAD — LU-20637 llapi: name a device scan's objects

- **Commit:** `bfd6650d3276` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 5.4M tokens, $3.16, 6m25s

## Overall assessment

Looks good. One optional documentation nit is inline for the next refresh; there's no need to re-spin for it.

## Findings

### 1. `Documentation/man1/lfs-find.1` (line 942)

(minor) This says the lookup through MOUNT needs CAP_DAC_READ_SEARCH, but ll_fid2path() also allows it when llite.*.user_fid2path is set:

    if (!capable(CAP_DAC_READ_SEARCH) &&
        !test_bit(LL_SBI_USER_FID2PATH, ll_i2sbi(inode)->ll_flags))

llapi_scan_rec_path.3 already describes both conditions. If the patch is refreshed, could this page say "unless llite.*.user_fid2path is set" too, so an unprivileged user on a site that enables it isn't told they can't use --fid2path on an OST?
