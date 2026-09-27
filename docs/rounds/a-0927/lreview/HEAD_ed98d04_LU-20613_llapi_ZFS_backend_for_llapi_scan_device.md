# HEAD — LU-20613 llapi: ZFS backend for llapi_scan_device

- **Commit:** `ed98d047c912` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 10.2M tokens, $5.54, 14m07s

## Overall assessment

Looks good. The libzpool usage checks out against the ZFS sources: the object walk, SA handle error paths, xattr spill layout, unlinked-set gating, directory size and block accounting all match osd-zfs. A few optional test and documentation points inline for whenever the patch is next refreshed; none of them needs a re-spin on its own.

## Findings

### 1. `lustre/tests/conf-sanity.sh` (line 13395)

(suggestion) The EBUSY refusal of an imported pool is what keeps a scan from reading a pool underneath its server, and lfs-find.1 documents it for --target, --fsname and --local. On ZFS this block is skipped, though, so nothing checks that refusal. While mds1 is still mounted, the ZFS branch could assert the documented answer:

    lfs find --target $mdt1svc   ->  fails, "in use: pool imported"

or let ENOTSUP through where the build has no backend. As it stands, a later change that stops detecting the kernel's import would still pass this test.

### 2. `lustre/tests/conf-sanity.sh` (line 13443)

(suggestion) This skip also fires when scan_osd_zfs.so was built and packaged but failed to load. scan_backend_load() turns a failed dlopen() or a missing dlsym() into the same -ENOTSUP as "configure found no libzpool headers". The ldiskfs half treats that as an error because the backend ships beside the osd plugin that mounted the MDT. With plugins, this backend now ships in lustre-osd-zfs-mount beside mount_osd_zfs.so, so the same reasoning applies. Could the skip be limited to a build that has no scan_osd_zfs.so at all, so that a packaged but unloadable plugin still fails? One way is to check the file on mds1, or the library's "no zfs device scan backend: ..." text. The OST branch and the lfs find skip below make the same trade.

### 3. `Documentation/man3/llapi_scan_device.3` (line 533)

(typo) This is off by one. scan_zfs_open() refuses strlen(device) >= sizeof(zt_pool), and zt_pool is ZFS_MAX_DATASET_NAME_LEN bytes including the NUL. So a name of exactly ZFS_MAX_DATASET_NAME_LEN characters is refused too. Maybe "is ZFS_MAX_DATASET_NAME_LEN characters or longer".
