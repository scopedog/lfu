# HEAD — LU-20650 lfs: add find --changelog, the log as source

- **Commit:** `5ce62b3458e9` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 3.6M tokens, $2.85, 4m53s

## Overall assessment

Looks good; one optional documentation question inline for whenever the patch is next refreshed - no need to re-spin for it.

## Findings

### 1. `Documentation/man1/lfs-find.1` (lines 832–841)

(minor) Is this caveat wider than "-printf or --projid" and "each file"?

Every --resolve lookup seems to open a directory, whatever the predicates. llapi_find_since() never hands llapi_scan_fid() less than

    st.fss_want = LLAPI_SCAN_FID | LLAPI_SCAN_MODE | LLAPI_SCAN_TYPE;

and FID and MODE are both in LLAPI_SCAN_MDT_MASK, so llapi_scan_fid() takes

    if (want & LLAPI_SCAN_MDT_MASK) {
            ...
            d = openat(mnt_fd, at, O_RDONLY | O_NDELAY | O_DIRECTORY);
            ...
            p = openat(mnt_fd, rp, O_RDONLY | O_NDELAY | O_DIRECTORY);

for the object itself when it is a directory and for its parent otherwise. mdd_open() does not look at the object's type before writing CL_OPEN, so assuming a client opendir reaches it as a file open does, each lookup puts a CL_OPEN (and the matching CL_CLOSE) for a directory into the log being read.

That is a different outcome from a file printed twice: the parent directory of every looked-up object can arrive as a record of its own and be printed, though the only event on it was the search's open. For example `--changelog all --resolve --since 1h -uid 1000` would list directories nothing touched in that hour. `-type f` hides it; most other searches do not.

If that reading is right, the same sentence in llapi_find_since.3 and in the commit message would want the same widening. Documentation only - if the patch is refreshed.
