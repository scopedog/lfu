# HEAD — LU-20606 llapi: scan an ldiskfs target directly

- **Commit:** `1bddb707ab5d` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 10.4M tokens, $5.38, 11m13s

## Overall assessment

Looks good; two optional points inline for whenever the patch is next refreshed. No need to re-spin for them.

## Findings

### 1. `lustre/utils/liblustreapi_scan_device.c` (line 625)

(minor) The decode here matches stat(2), but for a device node the two scanners still give different answers, because the namespace side does not decode. llapi_scan_namespace() copies lmd_stx from LL_IOC_MDC_GETINFO_V2, and ll_dir_ioctl() fills it from the raw value:

    stx.stx_rdev_major = MAJOR(body->mbo_rdev);
    stx.stx_rdev_minor = MINOR(body->mbo_rdev);

mbo_rdev is the old_encode_dev() value ll_mknod() sent. So for `mknod c 10 200` it is 0xac8, and a walk reports 0:2760 where this scan (and stat(2)) report 10:200. The llite side is pre-existing and not this patch's bug. Since the commit message says both scanners give the same answer for one file, would it be worth fixing ll_dir_ioctl() to use old_decode_dev(), as ll_update_inode() does, in a separate change? Until then, llapi_scan_namespace.3 could note the difference.

### 2. `Documentation/man3/llapi_scan_device.3` (line 213)

(minor) If the patch is refreshed, it would help to note the opposite case for hard links here. A device scan delivers one record per inode, with lfsr_name set to the first trusted.link entry only. A namespace walk delivers one record per directory entry, so a file with three names is three records there and one here. A consumer comparing counts between the two scanners would hit this as well as the striped-directory case described above.
