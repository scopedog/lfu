# Open bugs in the series, 2026-09-03

From reading **all 135 open AI review threads** across the 21 changes. 60 were
answered, and these are what is left that is a *defect* rather than wording.
Of the 16 threads the reviewer tagged `(defect)`, **15 were already fixed** —
the tags are not a guide, and the worst one below was tagged `(minor)`.

## 1. `sp_filter` can be copied torn and then called — 68094 `ea53773b`

The worst of them, and the one the tag hid.

    #define LLAPI_SCAN_PARAM_MIN_SIZE \
        ((__u32)(offsetof(struct llapi_scan_param, sp_want) + \
                 sizeof(((struct llapi_scan_param *)0)->sp_want)))   /* = 24 */

`sp_filter` is a **function pointer at offset 24**. The guard accepts
`sp_size` in [24, sizeof], then `memcpy(&spl, sp, sp->sp_size)` into a zeroed
`spl` — so an `sp_size` of 25–31 copies 1–7 bytes of the pointer, zero-fills
the rest, and the scan calls it.

**The same struct family already has the fix.**
`LLAPI_SCAN_CL_PARAM_MIN_SIZE` reaches *through* `sc_mdtname` for exactly this
reason, and says so: *"a minimum that stops short of it accepts a caller whose
struct never carried one and then reads a NULL out of the copy."* One struct
got it, the other did not. Two call sites in `liblustreapi_scan.c` (~565, ~713).

## 2. A `stat()` failure routes to ZFS — 68163 `16169694`

`scan_backend_kind()` returns `SCAN_BACKEND_ZFS` for anything `stat()` cannot
resolve, so on an ldiskfs-only build `lfind --device /dev/sdb99` prints
*"no zfs device scan backend"* and returns `-ENOTSUP`, naming ZFS on a node
that has none. It also collides with what `-ENOTSUP` is documented to mean
(*"this build has no backend for the target"*) and with how conf-sanity 165
keys its skip.

## 3. `sc_type_mask` silently dropped — 68415 `94de9663`

It reaches the kernel only through `llapi_changelog_start_user()`. On the
`sc_user == NULL` branch `llapi_changelog_start()` is called without it, so a
caller asking for `CL_UNLINK` alone reads **every** event type. The man page
says only that it is *"intersected with the registered user's own mask"* and
never that it is ignored without one.

## 4. The two scanners disagree on `--attrs` — 68156 `907b17a6`

`EXT2_COMPR_FL` and `EXT2_NODUMP_FL` are in the device scanner's `so_flags`
mask, but a namespace scan takes `sr_attr_flags` from what the MDT declares —
only IMMUTABLE, APPEND and (with crypto) ENCRYPTED. `chattr +d` therefore
makes `lfs find --attrs d` answer differently depending on which scanner ran.

## 5. Design gap: no public way to match a mount to a target — 68288 `222a9f0d`

`llapi_scan_rec_path.3` tells a caller they must establish that the mount and
the scanned target are the same filesystem, but nothing in
`<lustre/lustreapi.h>` exposes the target's fsname or label:
`scan_device_run()` is internal, `llapi_scan_device()` always passes
`want_fsname` NULL, and `llapi_scan_tgt`/`tt_label` live in a private header.
An out-of-tree user of the pairing the page documents cannot make the check.

## Not bugs, still open

Wording only: 68156 `ab78d3de`, 68158 `f82298cf` and `1343a02c`, 68160
`3af3a80a` and `6fd1845c`, 68288 `cf4e2efc`. Plus five on 68288 PS3 whose
verification came back ambiguous and were left unanswered rather than guessed:
`23080893`, `0d9ade6c`, `e968ee5e`, `98eafaba`, `4a1166de`.

Declined with reasons: the dirmap arena (68288 finding 7 from lreview).
Documented rather than fixed, by the user's call: the `-name` coalescing
asymmetry — see [[lfu-lreview]].

Held deliberately: the **osd-zfs FORTIFY_SOURCE** warning, ours to file — see
[[lfu-osd-zfs-fortify]].

## Why this list exists

`68156 80fcd9e7` — the LMV_USER_MAGIC bug — sat unanswered in the PS9 pile for
six patchsets until `lreview` rediscovered it independently on 2026-09-03. An
unanswered thread is a finding nobody is tracking. See [[lfu-lreview]] and
[[lfu-daily-routine]].
