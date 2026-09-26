# 21a9fe3a6d — LU-20637 llapi: name a device scan's objects

- **Commit:** `21a9fe3a6dde` (21a9fe3a6d, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 5.0M tokens, $3.02, 6m15s

## Overall assessment

Mostly good; a few minor comments inline. None of them needs a re-spin on its own; they can go in with the next refresh.

## Findings

### 1. `lustre/utils/lfs.c` (line 6521)

(minor) The sweep drops OSTs for --paths, but nothing here drops the targets of other filesystems for --fid2path. lfs_find_local_targets() is given fp_fsname, which is NULL for --local, so on a server that hosts targets of two filesystems:

    lfs find --local --fid2path /mnt/fs1 ...

reaches scan_device_run_prepass() for each fs2 target with want_fsname "fs1". Each of those fails with -EXDEV and prints "failed for ...", and the command exits non-zero even though every fs1 target was searched. Should a sweep with --fid2path skip targets whose label is not of the mount's filesystem (lfs_find_label_of() on the llapi_search_fsname() answer), the same way --paths skips OSTs? Or should --local with --fid2path be refused in favour of --fsname?

### 2. `Documentation/man3/llapi_scan_rec_path.3` (line 104)

(minor) For an MDT record this ioctl goes to the MDT that holds the object, and in a device scan that is the target being read. On a stopped MDT, llapi_fid2path_at() goes through the MDC to an import that is waiting for the MDT to come back, so it blocks rather than failing. That is why llapi_find_device() never calls this function on an MDT and builds the directory map instead (see the comment in find_decide() and lfs-find.1). The page only explains the safe OST case (the owner FID resolves against the MDT). Could NOTES say that on an MDT this is safe only while the target is in service? The map is internal (scan_dirmap_*() in lustreapi_internal.h), so a public llapi_scan_device() caller on a stopped MDT has no way to get pathnames short of llapi_find_device() with fp_paths. The kernel-doc above llapi_scan_rec_path() has the same gap.

### 3. `lustre/utils/lustreapi_internal.h` (line 575)

(style) This isn't a bug, but struct scan_dirent reuses the sd_ prefix that struct scan_dev in liblustreapi_scan_device.c already uses (sd_be, sd_tgt, sd_want, ...). Both structs appear in the same file, so grepping for sd_ now finds both. If the patch is refreshed, a distinct prefix such as sde_ would keep them apart.
