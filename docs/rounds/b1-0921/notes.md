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

## The lreview pass, and the finding that was wrong

Four commits, one at a time: 32.7M tokens, $28.40. **68163 came back clean.**
Eight findings on the other three, of which three are taken -- and one
reported as a defect is not one.

### The "defect" that was not

> `%Lh` is missing from `strchr("chiopS", c[1])`, so a device scan never asks
> for the LMV and every directory prints hash type "none".

The string is `"chiopS"`. Its second character is `h`. The set already
contains it, and the rest of the chain -- `find_device_want()` leaving out
`LLAPI_SCAN_LMV`, `find_rec_to_lmv()` memsetting, `mdt_hash_name[0]` printing
"none" -- never starts.

What makes this worth writing down is the order it came apart in. The fix was
written first and the lab could not reproduce the symptom: arm C, which was
supposed to show the defect, printed `fnv_1a_64` exactly like the fixed arm.
Two rounds of blaming the fixture followed -- a filesystem left mounted as ZFS
while the script scanned `/tmp/lustre-mdt1` as ldiskfs, then a `-name` in the
command that might have changed the demand mask -- before the obvious reading:
**a failed reproduction is evidence about the finding, not only about the
test.** An instrumented build of the pre-fix tree settled it:

    DEBUG want=0x4517000008ff lmv=1 needs_lmv=0

`lmv=1` with `needs_lmv=0` means `printf_format_want()` put it there, from
`%Lh`, before any fix. The transform was dropped; it had only duplicated the
letter.

### Taken

- **68159:** the commit message now says why an MDT object with no
  `trusted.lma` keeps `obj:ID` -- an IGIF needs the inode generation, and the
  record carries no field for it, so one built from the id alone would name a
  different object. That closes a thread carried since PS17.
- **68158:** the `llapi_lov_string_pattern()` join is listed under the loop's
  differences, where it happens, rather than as a helper exception.
- **68160:** lfs-find.1 now says a failure the command line caused ends the
  sweep, which is what `-ENOTSUP` does.

### Queued for the next round

`llapi_error()` already prints the program name, so 68160's `progname`
argument doubles it; the `# name (device)` header is keyed off the number of
targets found rather than the number scanned; `--target`/`--fsname` are only
exercised after `stopall`, where both are expected to fail, so
`lfs_find_label_of()` never runs successfully in the suite; and
`lfs_find_parse.h` now carries setquota/migrate/mirror option values and
helpers that are not find's.

## What batch 1 comes to

**No code change.** Three lines of man page in 68160 and two commit messages,
over `r0921c-tip`. Stack tip **`b1-tip` = 55a460f437**.

- Per-commit build sweep: 26/26 `build=0 hdr=0 tests=0`.
- lreview: all four covered at the trees being pushed -- the code is identical
  to what was reviewed, and the only tree change is a man page, a docs-only
  skip named here.
- The ZFS lab above, plus this morning's ldiskfs lab, cover the behaviour.
