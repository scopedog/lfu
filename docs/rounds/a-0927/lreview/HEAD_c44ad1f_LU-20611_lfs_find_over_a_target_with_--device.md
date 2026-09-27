# HEAD — LU-20611 lfs: find over a target, with --device

- **Commit:** `c44ad1ff635a` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 5.5M tokens, $3.03, 6m29s

## Overall assessment

Looks good. There are a few optional wording nits inline for the next refresh; there's no need to re-spin for them.

## Findings

### 1. `/COMMIT_MSG` (line 11)

(minor) If the message is refreshed: "Nothing needs to be mounted" holds for --device and a block-device argument, but --target, --fsname and --local find their device through osd-*.NAME.mntdev, which exists only while the target is mounted (the next paragraphs say so). The man page qualifies this ("For a device named with --device or given as a block device, nothing needs to be mounted"). Could the opening paragraph say the same?

### 2. `/COMMIT_MSG` (line 17)

(minor) lfs_find_is_device() probes with statx(AT_STATX_DONT_SYNC, STATX_TYPE) where HAVE_STATX is defined, and only falls back to stat() without it. That's a deliberate difference, because a type-only statx() avoids a glimpse, so it may be worth naming statx() here rather than stat().

### 3. `Documentation/man1/lfs-find.1` (line 886)

(minor) If the patch is refreshed: under --internal, an object with no trusted.lma has no FID, and llapi_find_device() prints it as obj:<id> instead (find_decide(), and the example in llapi_find_device(3)). Should this sentence, or the --internal entry above it, mention that form, so a script parsing the output doesn't expect only FIDs?
