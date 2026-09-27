# HEAD — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `b579f14d7a26` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 5.5M tokens, $3.29, 6m26s

## Overall assessment

Mostly good. A few minor points inline; none of them needs a re-spin on its own, so they can go into the next refresh if one happens.

## Findings

### 1. `lustre/utils/liblustreapi_scan_changelog.c` (line 384)

(minor) Can this set LLAPI_SCAN_LAZY_SIZE/LAZY_BLOCKS over a value that is not a lazy size at all?

With AT_STATX_DONT_SYNC, ll_getattr_dentry() returns lli_lazysize only when `stat->size == 0 && lli_attr_valid & OBD_MD_FLLAZYSIZE`. Otherwise it returns i_size_read(). For a regular file with no LSOM, ll_update_inode() leaves i_size alone. That happens for a file still open for write (the CL_CREATE has arrived but no close has sent a size yet), or a file whose size was never recorded. If the inode was only just instantiated by llapi_open_by_fid_at(), i_size is 0. So a consumer that asks for LLAPI_SCAN_LAZY_SIZE without LLAPI_SCAN_SIZE gets a size of 0 with the lazy bit set, for a file that is not empty.

The namespace scanner sets the same bit only when the MDT reported OBD_MD_FLLAZYSIZE (scan_rec_mdt()), and the device scanner only when trusted.som exists. So the same file reads as "no size" from those two and as "lazy size 0" from this one. The statx result cannot tell these cases apart. Would it be safer to leave the lazy bits clear here unless SOM is known to be present? That could be checked through LL_IOC_MDC_GETINFO or trusted.som, for example. lfs find always asks for LLAPI_SCAN_SIZE as well, so it glimpses and is not affected.

### 2. `lustre/utils/liblustreapi_scan_changelog.c` (line 364)

(minor) This isn't a bug, but under HAVE_STATX scan_cl_mdt_stat() already has a struct statx with the nanoseconds in it. They are dropped only because the result goes through a struct stat. So the comment above ("stat(2) is whole seconds here") describes a choice made here, not a limit of the call. The time fields then carry less precision than llapi_scan_namespace() returns for the same object. If the patch is refreshed, consider returning the statx itself (and STATX_BTIME with it), and keeping the struct stat conversion only for the fstat() fallback.

### 3. `lustre/utils/liblustreapi_scan_changelog.c` (line 806)

(minor) Is the pre-migration FID meant to be delivered as an object of its own? CLF_RENAME is also set on CL_MIGRATE records. mdd_migrate() passes tobj (the new FID) as the target and mdd_object_fid(sobj) (the old FID) as sfid. mdd_dir_layout_split() does the same. So one migrated object comes out as two records in event mode and as two cached objects in object mode, one of them under a FID that no longer exists. A resolve of that FID fails, so the record carries only the FID. The man page describes the two-record case only for a rename over an existing name. If this is intended, a sentence about CL_MIGRATE in llapi_scan_changelog.3 would help, because a consumer such as lfs find --since would otherwise report a stale FID as a changed object.
