# HEAD — LU-20606 llapi: scan an ldiskfs target directly

- **Commit:** `b3ef73f19c7a` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 8.4M tokens, $4.39, 8m51s

## Overall assessment

Looks good. There are two optional items inline for whenever the patch is next refreshed. Neither needs a re-spin.

## Findings

### 1. `Documentation/man3/llapi_scan_device.3` (line 45)

(minor) If the patch is refreshed: this list doesn't quite match scan_want_xattr().

A size also fetches trusted.lmv, which scan_size() uses to leave a striped directory's size out. And LLAPI_SCAN_LINKEA doesn't decide whether trusted.link is read, because it is always read. The paragraph a few lines further down says so itself.

Perhaps say that a size reads trusted.lov, trusted.som and trusted.lmv, and drop the LLAPI_SCAN_LINKEA clause, since that bit only controls whether the linkea is delivered.

### 2. `lustre/utils/liblustreapi_scan_device.c` (line 1011)

(suggestion) The comment above says a scan_osd_ldiskfs.so that doesn't match this library is a real possibility. The RPMs allow it too: lustre `Requires: %{name}-osd-mount` with no version.

This check only proves that the five symbols exist. struct llapi_scan_obj, llapi_scan_sink and llapi_scan_tgt are passed across the dlopen boundary by layout, and nothing checks the layout. If a later patch in the series changes one of them, an old plugin would read and write the wrong offsets without any error.

Could the plugin export a small ABI version, or sizeof(struct llapi_scan_obj), and have scan_backend_load() refuse a mismatch with -ENOTSUP, the same way it refuses a missing symbol? mount_osd_*.so has the same gap already, so this is optional.
