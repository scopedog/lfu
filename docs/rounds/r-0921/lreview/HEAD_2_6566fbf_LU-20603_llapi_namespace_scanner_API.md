# HEAD~2 — LU-20603 llapi: namespace scanner API

- **Commit:** `6566fbf2e342` (HEAD~2, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 14.9M tokens, $12.01, 18m54s

## Overall assessment

Looks good. The record/parameter contract, the validity masks and the lifetimes are all consistent with what the code does, and the new file compiles clean under -Wall -Wextra. Two optional inline notes for whenever this is next refreshed -- neither is a reason to re-spin.

## Findings

### 1. `lustre/utils/liblustreapi_scan.c` (line 598)

(minor) This is the first public API to let a caller pick a thread count, and the path it opens has a buffer size that does not match worth knowing about before the man page starts advertising it.

work_unit_create() allocates the path buffer as

    unit->fwu_path = malloc(PATH_MAX + 1);

but find_worker() hands it to the traversal as

    llapi_semantic_traverse(unit->fwu_path, 2 * PATH_MAX, -1, ...);

and that second argument is the only bound the walk has -- llapi_semantic_traverse() checks `(len + dent->d_reclen + 2) > size` before its two strcat()s. So a tree deeper than PATH_MAX writes past the allocation rather than stopping, for any scan with lfsp_thread_count > 1. The single-threaded side is fine (2 * PATH_MAX allocated, 2 * PATH_MAX + 1 declared, and d_reclen over-counts by the dirent header).

This is pre-existing -- it came with `lfs find --thread-count`, and nothing here changes it -- so not something to hold this patch for. Worth its own ticket though, since test1 already scans with 8 threads.

### 2. `lustre/utils/liblustreapi_scan.c` (line 425)

(minor) Should this reuse `d` the way the project id does?

The block just above passes `d != -1 ? &d : fdp` to get_projid(), but here an fd is only opened when `d == -1`, and the ioctl below then tests `*fdp`. For a regular file the scan already holds open -- a foreign symlink reached as a start point, where llapi_semantic_traverse()'s EINVAL retry opens without O_DIRECTORY -- `*fdp` stays -1 and LLAPI_SCAN_HSM is left clear even though a usable descriptor is in hand.

Narrow, and the bit staying clear is a truthful answer rather than a wrong one, so this is only a consistency point for a refresh.
