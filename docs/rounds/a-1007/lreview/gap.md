# e473ec9b43 — LU-20650 lfs: find --since, warn when the log was cleared

- **Commit:** `e473ec9b43c6` (e473ec9b43, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 1.9M tokens, $1.56, 5m47s

## Overall assessment

Looks good; two optional minors inline for whenever the patch is next refreshed — no need to re-spin for them.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 5224)

(minor) `--since 0` and `--since 1` read the same records: `sc_startrec` 0 means "from the oldest", and indexes start at 1. Only `--since 1` gets the warning, though, because index 0 is treated here as "no anchor".

After a clear, both runs return the same short answer, but `--since 0` says nothing. Is that intended? If 0 is meant to mean "whatever the log holds", it may be worth a word in lfs-find.1. Otherwise, dropping the `fp_since_index == 0` test would make the two behave the same.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5208)

(minor) Is "a log that still holds record 1 has lost nothing" always true? mdd_changelog_init() starts `mc_index` at 0 and only moves it up from the records and user records it finds. So a log emptied by deregistering its last user (by hand, or by changelog GC) restarts at 1 after the MDT is remounted. lfs-find.1 describes this restart under `--since-cookie`.

In that case a time anchor that reaches back before the restart gets no warning, even though the old records inside the window are gone. If warning there is not wanted, perhaps reword the claim (here, in the commit message and in llapi_find_since.3) to "has lost nothing since the log (re)started".
