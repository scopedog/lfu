# dba64d2b45 — LU-20611 llapi: run find over a device scan

- **Commit:** `dba64d2b45ec` (dba64d2b45, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 8.2M tokens, $4.16, 9m28s

## Overall assessment

Looks good; one optional nit inline for whenever the patch is next refreshed. No need to re-spin for it.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 4337)

(style) This isn't a bug, but this warning is the only message in llapi_find_device() that doesn't start with the target. The undecided warning just above does ("%s: %llu objects could not be decided ..."). A caller sweeping several devices with one search gets "12 of 40000 objects were skipped" and can't tell which device it was about. If the patch is refreshed, consider:

    "%s: %llu of %llu objects were skipped: unreadable or inconsistent on the target", target, ...
