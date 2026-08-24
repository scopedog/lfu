# LU-20637: FID to pathname Output Format

**Filed 2026-08-24 as LU-20637**, pushed the same day as
[68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288). Technical task, **parent LU-20462**, related to **LU-20606**
(`llapi_scan_device()`, whose records carry the FIDs this names) and
**LU-20611** (`lfind(8)`, the consumer that grows the option).
Assignee Hiroshi Nishida, Affects Version **2.18.0**. The LU project defines no
components, so that field stays empty as it does on every other ticket there.

One of the nine modules the HLD marks mandatory for the initial
implementation, and the only one with no dependency on the Object Stream
format. See [`plan-2.18.md`](../plan-2.18.md) §E. Lab record:
[`t166-fid2path-lab.txt`](../../bench-data/2026-08-24/t166-fid2path-lab.txt).

---

## Summary line

```
LFU: Output Format module to generate pathnames from FIDs
```

## Description, paste-ready

Written without double hyphens, asterisks or braces in the prose, with every
literal name inside a code block, so Jira's editor has nothing to autoformat.
Paste the whole of the following.

---

A scan of a Lustre target reads objects off the device. It holds names and
parent FIDs but no pathnames, so `lfind(8)` reports objects by FID and a user
cannot turn one into a path.

The High Level Design asks the initial Output Format module for both: text
printing of FIDs, which exists, and generating pathnames for them, which does
not.

Add a call that names the object a scan record describes:

```
int llapi_scan_rec_path(int mnt_fd, const char *mnt_path,
                        const struct llapi_scan_rec *rec,
                        char *buf, size_t buflen);
```

It uses the path a namespace scan already recorded, and resolves the FID
through a client mount when there is none.

Add the option that uses it, where MOUNT is a client mount of the same
filesystem:

```
lfind --device DEVICE --fid2path MOUNT --type f
```

Without it, `lfind` prints FIDs as before.

Three behaviours a consumer will see:

Resolution costs one ioctl per match, so it runs on the objects a search kept
and not on every object scanned. That is why it is an option and not the
default.

An object with no pathname is counted and reported at the end, not printed. An
OST data object, and a target's own objects, never have one.

A hardlinked object is printed once, under its first name, because the scan
enumerates objects rather than names.

## Acceptance

conf-sanity test_166, ldiskfs only, because reading a target that is in service
is what a ZFS pool refuses. It creates twenty files and one hardlink, giving
twenty one names over twenty objects, then asserts that every unambiguously
named object comes back, that twenty paths are printed and not twenty one, that
one of the hardlinked pair appears, and that no FID appears where a path was
asked for.

```
PASS 166
client sees 21 names over 20 objects
--fid2path resolved 20 objects from 21 names, hardlink once
```

---

## Implemented 2026-08-24, held locally

Committed on the `lu-20603-scan-api` worktree as **`LU-20637 llapi: name a
device scan's objects`**. It was tagged with the epic until the ticket existed;
retagged 2026-08-24, a message-only amend that left the tree byte-identical and
the Change-Id intact.

Touches `include/lustre/lustreapi.h`, `lustre/utils/liblustreapi_scan.c`,
`lustre/utils/liblustreapi_pfind.c`, `lustre/utils/lfind.c`,
`Documentation/man3/llapi_scan_rec_path.3` (new),
`Documentation/man8/lfind.8`, `lustre/tests/conf-sanity.sh`.

Verified: all ten commits build individually with no `-Wall -Werror`
diagnostics, checkpatch strict reports zero errors on all ten, checkpatch-man
clean, and conf-sanity 165 and 166 both pass on a lab, run together and
standalone.

What was decided in the code, beyond the ticket text:

- **`fp_fid2path_mnt` is a path, not a descriptor.** A zeroed `struct
  find_param` gives 0, which is a valid file descriptor and would have meant
  "resolve against stdin". A NULL pointer is unambiguous. The same trap the
  2026-08-24 review found on `fp_max_depth`, avoided rather than repeated.
- **`fc_mnt_fd` is set to -1 explicitly in `cb_find_init()`**, whose
  `struct find_ctx` is `{ 0 }` initialised, for the same reason.
- **One open per scan, not per object.** `llapi_find_device()` opens the mount
  once and closes it after; `llapi_fid2path()` would have opened and closed it
  per call.
- **The resolver returns `-ENODATA` when the record has neither a path nor a
  FID**, distinct from `-ENOENT` when the object genuinely has no pathname, so
  a consumer can tell "nothing to go on" from "no name exists".

## What this does not do

- No path is reconstructed from `sr_linkea` and `sr_parent_fid` within the
  scan. That would avoid the ioctl but needs a FID to record map of the whole
  namespace, which is the walk the device scanner exists to avoid.
- Nothing here helps a target with no client mount available. That is inherent:
  a pathname is a namespace fact and only a mounted client has the namespace.
