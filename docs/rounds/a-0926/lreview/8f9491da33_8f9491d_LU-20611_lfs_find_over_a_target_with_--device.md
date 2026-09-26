# 8f9491da33 — LU-20611 lfs: find over a target, with --device

- **Commit:** `8f9491da3322` (8f9491da33, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 7.0M tokens, $3.64, 8m10s

## Overall assessment

Looks good; two optional minor points inline for whenever the patch is next refreshed. No need to re-spin for them.

## Findings

### 1. `Documentation/man1/lfs-find.1` (line 938)

(minor) `--ls` is refused against a target too, but it isn't in this list. It expands to a -printf format ending in `%p`, so `lfs find --device /dev/vdb --ls` fails in find_device_supported() with "-printf %p needs a path", which names an option the user never typed. If the patch is refreshed, maybe add `--ls` here, or refuse it by name in lfs_find_device() next to --maxdepth and --threads so the message matches what was typed.

### 2. `lustre/utils/lfs.c` (line 6473)

(minor) On a node where the MGS is mounted, `lfs find --target MGS` reports "no target 'MGS' mounted here". lfs_find_local_targets() drops the MGS through the -MDT/-OST test before it compares the name against @want, so the message is wrong for that one name. It isn't a bug, but if the patch is refreshed, saying that the MGS can't be searched would be clearer.
