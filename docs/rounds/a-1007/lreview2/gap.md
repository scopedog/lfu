# 2c900d0b60 — LU-20650 lfs: find --since, warn when the log was cleared

- **Commit:** `2c900d0b6036` (2c900d0b60, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 2.4M tokens, $1.73, 3m25s

## Overall assessment

Mostly good; the minor points inline can ride along on the next refresh, no need to re-spin for them.

## Findings

### 1. `/COMMIT_MSG` (line 22)

(style) A blank line seems to be missing before "For a bare index ..."; as it stands the index/time paragraph runs straight on from the record-1 paragraph.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5242)

(minor) An empty log (oldest == 0) returns here without a warning, but that is also a log whose records were all cleared. Take a policy engine that has caught up on an MDT that has since gone idle: it has cleared everything, so `--since 1d` (or `--since 5` where the MDT's current index is 1000) returns nothing, exits 0, and says nothing. That is the same short answer the commit message describes.

lfs-find(1) says that "when an MDT's log no longer reaches back to TIME or INDEX, a warning names the MDT", and that is not true for this case. Could this print the hedged time-style warning when the log is empty, or could the man pages and the comment above list the empty log alongside the restarted-at-1 exception?

### 3. `lustre/utils/liblustreapi_pfind.c` (line 6652)

(minor) If the probe in find_cl_first() fails, find_since_gap() drops the error, but llapi_scan_changelog() has already printed "cannot read <mdt>'s changelog" for a failed llapi_changelog_start(). The scan below then fails in the same way and prints that line again, followed by the "cannot read the changelog of" line. A user without access to /dev/changelog-* (the -EACCES case in llapi_find_since(3)) now sees the same error twice for every --since run. Would it make sense to do the probe after the scan has opened the log, or to make the probe quiet?
