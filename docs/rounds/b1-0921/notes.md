# Batch 1, 2026-09-21 — 68158, 68159, 68160, 68163

The first of the four batches in the board's push plan. Gate before pushing:
the four pushed this morning green on jenkins and Janitor initial testing.

## The open threads: five, all already fixed

Counted by the last-reply rule off the REST `comments` endpoint (the thread
view under-reports inline comments). 68158 and 68159 had none. Every one of
the five was already answered by the unpushed rounds, so this batch needed no
new code:

| Thread | Where it stands in `r0921c-tip` |
|---|---|
| 68160: `${sdir:+--search $sdir}` is inert, and `sdir` is not `local` | `local sdir=""` at conf-sanity.sh:13393, and `--search` is a real option — `lfs_find_parse.c:1168` has it with `required_argument`. The r3-0913 round took the dead expansion out of the other invocation |
| 68160: `lfind`'s single-dash pre-pass mis-describes `-target`/`-internal` | Moot: `lfind.c` no longer exists. It was folded into `lfs find --device` on 2026-09-11 after Andreas's CR-1 |
| 68163: the message says `scan_backend_kind()` needs no slash case | Reworded by r3-0913: "scan_backend_kind() also takes such a name as ldiskfs before its own stat(), so a mount point or another directory is never sent to the ZFS backend" |
| 68163: a ZAP lookup per object on the shared unlinked set | Fixed: `zap_count()` at open clears `zt_unlinked` when the set is empty, and the per-object lookup is gated on it (libscan_zfs.c:377-383) |
| 68163: `STATX_ATTR_NODUMP` makes one predicate answer two ways | Fixed: the ZFS backend declares `IMMUTABLE\|APPEND` like ldiskfs, with a comment saying why NODUMP is left out; the man-page sentence went with it |

## The ZFS lab

68163 is the ZFS backend, so this batch is where the round-20/21 device-scan
changes had to be shown on ZFS rather than ldiskfs. Scripts:
[`r21zfs.sh`](r21zfs.sh), [`r21zfs2.sh`](r21zfs2.sh); log
[`zfsarms.log`](zfsarms.log). Arms as before, chosen by `LD_PRELOAD`:
A = `r0920-tip`, B = `r0921-tip`, C = `r0921b-tip`.

The ZFS backend itself is a dlopen'd plugin and `libscan_zfs.c` does not
differ across the arms, so only `liblustreapi` — where `scan_size()` lives —
changes between them. The installed plugins under `~/r18-inst/lib/lustre`
were three days stale and are what `PLUGIN_DIR` finds first, so they were
refreshed from today's build before any arm ran: that is the scan-plugin trap,
and it would have invalidated the run silently.

1. **An OST data object keeps its blocks.** arm B `4194304 0`, arm C
   `4194304 8198`, against the client's `stat` of 8199 — the object's own
   blocks, where the client's number includes the MDT inode. The lreview
   defect is fixed on ZFS as on ldiskfs.
2. **A striped directory's size is withheld.** arm A `16384 12`, arm C `0 0`.
   This needed arm **A**, not B: the withholding came in the first r0921 pass,
   so B and C both have it and a B/C comparison showed nothing. The master
   has to be on MDT0000 for the scan to reach it in the pool that exports
   cleanly, hence `setdirstripe -c 2 -i 0`.
3. **The attrs gate, which the ldiskfs lab could not show.** On ldiskfs every
   object reports `OBD_MD_FLFLAGS`, so arms A and C were identical there and
   the morning's run could only prove "nothing regressed". A ZFS MDT sets that
   bit **only when the object has flags**, so the same walk separates them:

   | object | arm A | arm C |
   |---|---|---|
   | `immf` (`chattr +i`, `stx_attributes=0x10`) | attrs=yes | attrs=yes |
   | `plain`, `sub`, `f`, the parent directory | attrs=yes, value 0 | attrs=**no** |

   Arm A claims the attributes were answered for four objects whose flags the
   MDT never sent; arm C claims it only for the one that has a flag. That is
   the distinction `lfsr_valid` exists for, demonstrated rather than argued.
   `lfs find --attrs Immutable` finds `immf` and only `immf` in both arms, so
   nothing user-visible moved.

## Two lab traps worth keeping

- **`llmountcleanup.sh` leaves the pools imported**, and the ZFS scan refuses
  one: `in use: pool imported, or dataset held`. Export every pool after the
  unmount. `lustre-mdt2` would not export even with `-f` while the MGS was
  still up, which is why the fixture puts the master on MDT0000.
- **Pick the arms from where the change entered the stack.** The first ZFS run
  compared B and C for a change that landed in B, and read "no difference" as
  a failure. The arm that predates the change is the only one that can show
  it.
