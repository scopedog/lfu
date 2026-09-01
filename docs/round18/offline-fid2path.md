# LU-20637: naming a target's objects without asking the target

2026-09-01, after round 17 was pushed.  In 68288, unpushed.

## The contradiction

`lfind --device <target> --fid2path <mount>` resolved every object by its
**own** FID.  That routes to the target holding it -- an OST object through
the OSC, an MDT object through the MDC.  But a scan reads a target that is
out of service, and for ZFS it *must* be: the backend refuses an imported
pool, at pool granularity, so a snapshot does not help either (measured).

So the two halves could not both be satisfied, and the failure was a hang
rather than an error:

    osc_ioc_fid2path -> obd_get_info -> osc_get_info
                     -> ptlrpc_queue_wait -> wait_woken

Measured on ZFS first, then reproduced on ldiskfs by unmounting a registered
OST -- which proved it was never a ZFS bug at all, only a case ZFS forces.

## What replaced it

Neither half now asks anything of the scanned target.

**An OST object is named by the file that owns it.**  `trusted.fid` carries
`ff_parent`, the owner's MDT FID; the lookup then goes to the MDT, which is
up.  Every version of that xattr (`filter_fid_18_23`, `_24_29`, `_210`,
`filter_fid`) leads with `ff_parent`, so only the `lu_fid` at the front is
read.  Two traps: the bytes are little-endian on disk, and `f_ver` is not a
version -- `f_stripe_idx` is `#define`d to it, so leaving it in place makes
every object of a striped file a different FID.

**An MDT object is named from its linkea plus a map of the target's
directories**, FID to (parent, name), built by a pass over the target before
the search.  A pass of its own because objects arrive in inode order, so an
object is usually delivered before its ancestors; resolving inline would mean
buffering every match to the end.  The pass asks for no layout, no SOM and no
HSM, and stops at the first object on an OST.

**No fall back to the lookup once the map is in use.**  The map is used
precisely when the target cannot answer, so one object it could not place
would stop the whole search there.

## `--paths`: no mount at all

Added the same evening.  `--fid2path` still needs a mount -- not to resolve
anything, but as the filesystem the paths hang from and for the
wrong-filesystem comparison -- and a filesystem whose only MDT is the target
being scanned has none to give.  For a single-MDT **ZFS** filesystem that is
every scan of its MDT, the pool having to be exported.

`--paths` composes the same names with no mount, printing them relative to
the filesystem root.  Nothing is asked of any running service.  Measured with
the whole filesystem torn down -- no client, no MDT, no OST -- scanning the
raw backing image: **8/8, identical to what the client saw beforehand.**

It is an MDT target only, and refused on an OST rather than answered with
every object nameless: an OST object is named by the file that owns it, and
that name lives on an MDT.  It cannot be combined with `--fid2path`.

The change was small because the walk never needed the mount: the map path
was merely gated behind `fc_mnt_fd >= 0`.

## A missing device said the wrong thing

`scan_backend_kind()` answers ZFS for anything that is not a block device or
a regular file -- right for a dataset name, which does not stat, and wrong
for `/dev/mapper/gone`.  A mistyped or torn-down device was reported as a
**missing ZFS backend**, sending the reader after a package instead of at the
name they typed.  Now `cannot scan '<dev>': No such file or directory`.  Only
a leading `/` separates the two cases, a dataset name never having one.

Predicted when the round-18 refusal was being designed, and acted on only
when a failing test produced the confusing message for real.

## Two documented limits, both counted rather than hidden

- An OST object no file owns yet -- precreated, never written -- carries no
  `trusted.fid` and has no name.  A target holds many; they are the *first*
  objects a scan meets, which is why the fallback was fatal rather than rare.
- On DNE the map covers only the scanned target, so an object whose ancestors
  live on another MDT cannot be placed.

## Verified

| | ldiskfs | ZFS, pool exported |
|---|---|---|
| OST via trusted.fid | 12/12; conf-sanity 167 PASS x2 | 10/10, identical to the client's list |
| MDT via linkea walk | 9/9 offline, = mounted baseline | 10/10, identical to the client's list |
| conf-sanity 165, 166, 167 | PASS x2 each, 0 skips | -- |
| `--paths`, whole filesystem down | 8/8, identical to the client's list | (same code path) |

Build clean under `-Wall -Werror`; no new checkpatch findings; no ERRORs.

## What the tests had to assert, and why

Every early version of these tests passed for the wrong reason:

- an **empty** target gave 0 lines in every arm and read as "did not
  reproduce";
- `createmany` alone makes precreated objects, which are *rightly* nameless,
  so the files must be written;
- a scan that resolved nothing and one that resolved everything both exit 0,
  so the assertion is the **set of names**, compared against what the client
  saw before the target went down.

The comparison arm found a regression no amount of review did: removing the
fallback exposed that the map path had never worked, because
`find_device_want()` only asked for the linkea when `-name` was given.  The
ioctl had been silently covering for it whenever the target was up.
