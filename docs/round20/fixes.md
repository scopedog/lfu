# Round 20: the five open bugs, fixed

All five from `docs/round19/open-bugs.md`, each verified against the tree
before and after.

## 1. `sp_filter` could be copied torn and then called — 68094 + 3 sites

`LLAPI_SCAN_PARAM_MIN_SIZE` is 24 and `sp_filter` is a function pointer
ending at 32, so an `sp_size` of 25–31 passed the range test and `memcpy`
left the pointer built from some of the caller's bytes and some zeros. The
range test could never have caught it: `sp_stats` [40,48) and `sp_search`
[48,56) tear the same way, so raising the minimum would only have moved the
hole.

`scan_param_whole()` in `lustreapi_internal.h` rounds the copy length down to
the last whole field, which is what a short size already means — and the
field it stops inside is exactly the one to drop. Applied at **all four**
copy-in sites: `liblustreapi_scan.c` ×2, `liblustreapi_scan_device.c`,
`liblustreapi_pfind.c`.

The field list grows with the struct: 68094 seeds it, 68156 adds `sp_stats`,
68163 `sp_search`, 68288 `sp_fsname`.

**Where the fix came from:** `LLAPI_SCAN_CL_PARAM_MIN_SIZE` already reaches
*through* its last pointer for exactly this reason and says so in a comment.
One struct in the family had the defence and the other did not.

## 2. A `stat()` failure routed to the ZFS backend — 68163

`scan_backend_kind()` returned `SCAN_BACKEND_ZFS` for anything `stat()` could
not resolve. `stat()` failing is ordinary for a ZFS target — a dataset is
`pool/dataset`, not a path — but a name beginning with `/` was meant to be a
path, so a missing device is the ldiskfs backend's to report.

Measured on the lab with two built copies of `liblustreapi.so`:

| | `lfind --device /dev/sdb99` |
|---|---|
| before | `lfind: /dev/sdb99: Invalid argument` |
| after | `lfind: cannot scan '/dev/sdb99': No such file or directory (2)` |

## 3. `sc_type_mask` silently dropped — 68415

It reaches the server only through `llapi_changelog_start_user()`, so with
`sc_user == NULL` a caller asking for `CL_UNLINK` alone read every event type
and nothing said so. Refused with `-EINVAL` rather than filtered client-side:
the records would still cross the wire, and `sc_filter` is already the
client-side spelling. `llapi_scan_changelog.3` says so now.

## 4. The two scanners disagreed on `--attrs` — 68156

`ll_dir_ioctl()` puts only IMMUTABLE, APPEND and (with crypto) ENCRYPTED into
`stx_attributes_mask`, and a namespace scan takes `sr_attr_flags` from it. The
device scanner also reported `EXT2_COMPR_FL` and `EXT2_NODUMP_FL`, so one file
answered `lfs find --attrs d` differently depending on which scanner ran —
against `sr_attr_flags` meaning one thing whichever filled it. Narrowed to the
three.

The bit is on the MDT inode either way; making it *answerable* is llite's to
do, for both scanners at once. Said so in the comment.

## 5. No public way to match a mount to a target — 68288

`llapi_scan_rec_path.3` told callers they must establish that the mount and
the scanned target are the same filesystem, and nothing public let them.
`sp_fsname` is the existing internal `want_fsname` under a public name: the
scan refuses a mismatched target with `-EXDEV`.

It has to be the scan that does it — only the scan reads the target's label,
and FID sequences are not unique across filesystems, so a lookup on the wrong
mount succeeds and answers with that filesystem's pathname. Documented in
`llapi_scan_device.3`, and the misleading EXAMPLES comment in
`llapi_scan_rec_path.3` now points at the field instead of at the caller.

## Verification

`-Werror` clean, every one of the 18 checkpatch counts at baseline, all five
present at the tip after seven amend-and-rebase rounds, and the ZFS-routing
fix measured before and after on the lab.
