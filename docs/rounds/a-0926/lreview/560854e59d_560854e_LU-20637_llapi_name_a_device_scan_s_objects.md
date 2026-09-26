# 560854e59d — LU-20637 llapi: name a device scan's objects

- **Commit:** `560854e59db2` (560854e59d, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 5.7M tokens, $3.21, 5m28s

## Overall assessment

Mostly good. One real issue inline: the --local --fid2path prefilter mishandles a bare fsname. The other comment is minor and can wait for the next refresh.

## Findings

### 1. `lustre/utils/lfs.c` (line 6491)

(defect) This passes the raw --fid2path argument to llapi_search_fsname(), which treats it as a path. llapi_find_device() instead treats an argument that does not start with '/' as an fsname (the llapi_root_path_open() / llapi_search_rootpath() branch). With a bare fsname, e.g.

    cd /mnt/otherfs; lfs find --local --fid2path testfs --type f

get_file_dev("testfs") fails, llapi_search_fsname() falls back to dirname() = ".", and it answers with the filesystem of the cwd. From inside another Lustre mount, fsname becomes "otherfs": the sweep reads only otherfs's targets, and each one then fails -EXDEV against testfs's mount. From a non-Lustre cwd, get_root_path() prints "dev not on a mounted Lustre filesystem", fsname stays NULL, and every local target is read, so targets of other filesystems fail -EXDEV.

The commit message says a bare fsname works, and lfs-find.1 says --local reads only the targets of MOUNT's filesystem. Could this use fp_fid2path_mnt directly as the fsname when it does not begin with '/', the same way llapi_find_device() does?

### 2. `lustre/utils/liblustreapi_pfind.c` (line 4487)

(minor) If the patch is refreshed: this paragraph no longer matches the code. On an MDT, fp_fid2path_mnt resolves nothing. The path comes from the directory map, and the mount only supplies the prefix and the fsname to compare, as llapi_find_device.3 now says. Also, lfs find does not set lfsp_fsname. The pairing goes through the mount's fsname (mfs), which is passed to scan_device_run_prepass() as want_fsname.
