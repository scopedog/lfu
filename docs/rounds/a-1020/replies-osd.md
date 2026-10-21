# Replies on the OSD series after the 10-20 push: 68818 posted by the user; 68810 POSTED 10-21 06:11 UTC (resolved)

Each reply goes on the thread's own patchset (PS1), `unresolved: false`.

## 68818 PS1, thread 160fe0e5 (adilger, llapi_scan_mount.3:85, CAP defect)
Our 09-11 reply said "Done" but the code still checked CAP_SYS_ADMIN.

> Correction: my reply above was premature, mdc_lfu_scan() still checked
> CAP_SYS_ADMIN. It checks CAP_DAC_READ_SEARCH as of PS3.

## 68818 PS1, thread 859434fd (adilger, liblustreapi_scan_device.c:1472, multi-tenant)
Our 09-11 reply described a server check that did not exist yet.

> Correction: the server check I described was not there yet. It is now,
> in 69851: admin and byfid_ops are required, and a nodemap with an ID
> offset gets only the objects whose UID and GID are in its range, with
> the IDs mapped. The RBAC role question is on LU-20730.

## 68810 PS1, thread 442b874f (ablagodarenko, osd_scrub.c:743, el10 build)
Still open; our reply said "fixed in my local commit".

> Done in PS2: the timestamps go through inode_get_[amc]time_sec().
