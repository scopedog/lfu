# The record carries a struct statx — 2026-09-04

adilger, on 68094: *"it seems unfortunate to expose a new struct
llapi_scan_rec"* — why eleven fields of our own for what the MDT ioctl
already hands over as a `statx`?

Implemented whole on branch `statx-spike` (`e753228aa2`), backup
`statx-backup-0628`.

## The design fork, and what was chosen

`sp_want` and `sr_valid` shared one vocabulary. Moving the eleven statx
fields into `sr_stx.stx_mask` would have broken that: ask with
`LLAPI_SCAN_SIZE`, check `STATX_SIZE`.

Chosen (option 2 of three): **the low `LLAPI_SCAN_*` bits are aliases of
the kernel's `STATX_*` values**, so they cannot drift; the API's own bits
move above bit 31. One vocabulary asks, two masks report, each owning the
half of the record it describes. `sr_valid`'s low half is reserved and
always zero.

Rejected: two vocabularies (asymmetric, and the wart a reviewer notices);
filling both masks (the duplication he objected to).

## Three things the implementation settled

- **`STATX_INO` is deliberately not aliased.** `LLAPI_SCAN_INO` is the
  object's id on the target (`obj->so_id`, the ldiskfs inode);
  `stx_ino` is `cl_fid_build_ino()`'s client inode. Different numbers,
  so they cannot share a bit. Found by checking the producers, not by
  reading the names.
- **`LLAPI_SCAN_ATTRS` stays ours.** statx has no mask bit for
  `stx_attributes` — only `stx_attributes_mask` — so the eleven twins are
  TYPE/MODE/NLINK/UID/GID/SIZE/BLOCKS/ATIME/MTIME/CTIME/BTIME, and ATTRS
  is not one of them.
- **The device scanner must still set `stx_attributes_mask`.**
  `find_check_attrs()` computes `stx_attributes_mask & stx_attributes`,
  so leaving the mask zero — the honest value, since no backend declares
  its set — would have made `lfs find --attrs` silently stop matching on
  a device scan. The fixed superset `find_rec_to_lmd()` used moved to
  where statx says it belongs.

## What the compiler could not catch

Three sites tested `rec->sr_valid & LLAPI_SCAN_MODE|SIZE` without naming
a renamed field. They compile, and would have been **always false**:
`liblustreapi_pfind.c` `fp_get_lmv` and the `--since` type guard, and
`llapi_scan_changelog_test.c`'s resolved counter. Found by grepping for
each mask tested against the wrong half, not by building.

That grep is the tool this change needs, and it is worth keeping:

    grep -rn "sr_valid[^;]*LLAPI_SCAN_\(TYPE\|MODE\|...\)\b"
    grep -rn "stx_mask[^;]*LLAPI_SCAN_\(FID\|ATTRS\|...\)"

## Cost

`find_rec_to_lmd()`: **119 lines to 34** — it was unpacking a statx into
fields and packing them back into a statx. `scan_rec_mdt()` loses 17
statx-derived lines and becomes a struct copy.

Against that, the record grows **328 -> 512 bytes**, most of it `struct
statx` padding we never use, and it is memset per object. Not measured
against the device scanner's 2.03M obj/s.

The timestamps are now whole `struct statx_timestamp`, so an incremental
scan keyed on `sr_stx.stx_mtime` has the nanoseconds the MDT recorded —
which the `__s64` whole-seconds fields threw away. The device and
changelog scanners still fill whole seconds; their sources have no more.

## Verified on the lab, 2026-09-04

`rhel9.7-server-mgs-mds-clone`, ldiskfs, MDSCOUNT=2. Userspace synced
file-for-file (22 files, md5-verified), utils **and** tests rebuilt, and
`/usr/bin/lfind` installed by hand — `make install` had left it stale
from a previous session, which with a struct that grew 184 bytes is
exactly the ABI mismatch the round-18 README warns about.

| | |
|---|---|
| `sanity` 56El,157c,160aa-ad,160y,160z ×2 | 16 PASS, 0 FAIL, 0 SKIP |
| `llapi_scan_test` | 11/11 |
| `llapi_scan_device_test` (real MDT image) | 7/7 |
| `llapi_scan_changelog_test` | 5/5 — **first ever run** |
| `04-arms-r18.sh` | 14/14 |
| `05-arms-cookie.sh` | 8/8 |
| `06-arms-clmark.sh` | 3/3 |

The decisive arms are the demand-mask ones, since the renumbering is what
could break them: `llapi_scan_test` test4, `llapi_scan_device_test`
test2/test3, and `llapi_scan_changelog_test` test2 — "no size when
unasked; 1 of 5 resolved when asked", which is the `stx_mask & STATX_SIZE`
line, end to end.

**A trap: `/tmp/lab-r18.log` is reused.** Reading it early gave a
complete green tally from the *previous* session's run. The timestamps
are what gave it away (13:39 yesterday vs 06:56 today). Assert the log's
own timestamps, not just its verdicts.

## Not done

The port down into the series. The change spreads across ten of the
eighteen commits, so each has to introduce its code already in statx
form. Until then it is one commit at the tip.
