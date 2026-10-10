# HEAD — LU-20650 lfs: add find --changelog, the log as source

- **Commit:** `b297adfbdcb6` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 4.4M tokens, $3.40, 6m18s

## Overall assessment

Looks good. One optional documentation point inline for whenever the patch is next refreshed - no need to re-spin for it.

## Findings

### 1. `Documentation/man1/lfs-find.1` (lines 832–841)

(minor) Is the feedback limited to -printf and --projid, and to files?

Every --resolve lookup goes through llapi_scan_fid(), and the cheapest demand mask it is given (LLAPI_SCAN_FID | LLAPI_SCAN_MODE | LLAPI_SCAN_TYPE) is inside LLAPI_SCAN_MDT_MASK, so it always opens a directory before the gather:

    find_since_cand_cb()
      llapi_scan_fid()
        openat(mnt_fd, at, O_RDONLY | O_NDELAY | O_DIRECTORY)   /* the object, if a directory */
        openat(mnt_fd, rp, O_RDONLY | O_NDELAY | O_DIRECTORY)   /* otherwise its parent */

llite sends an MDS open for a directory as well, and mdd_open() records CL_OPEN for any object type. So with OPEN in the mask, a plain `--changelog all --resolve` looks to be enough: the parent directory of each object looked up gets a CL_OPEN of its own, arrives later in the same read as a record with no name and no type, is looked up in turn (which opens it again) and is printed, although nothing but the search touched it.

That is a different effect from "a file can then be printed again": objects that had no event of their own enter the answer. If that is right, could this paragraph say so? The commit message and llapi_find_since.3 carry the same sentence.
