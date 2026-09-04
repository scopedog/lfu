# 68163's AI review — one real doc conflict, one already fixed

## `effcf38f` — already fixed

It asks for `1ULL << 48` to be spelled `DN_MAX_OBJECT`, since
`<sys/dnode.h>` is already included. The tree already reads

    /* The whole id space, as <sys/dnode.h> defines it. ... */
    #define SCAN_CHUNKS_MAX		(DN_MAX_OBJECT / SCAN_CHUNK_OBJS)

That was one of round 20's earlier lreview fixes on this change. The
comment is on **PS15**, which predates them — another instance of the
gap the push case describes.

## `019bb14e` — real, and the two pages did disagree

`lfind.8` told the reader, of a ZFS target in service:

> Scan a snapshot of an exported pool, or **a failover partner's copy**,
> instead.

Neither escape works as written, and `scan_zfs_import()` says so:

    if (... state == POOL_STATE_ACTIVE) {
            ...
            return -EBUSY;

A pool is `ACTIVE` while imported **anywhere** — including on the
failover partner, and including after a crash left it dirty — so a
partner's copy on shared storage is refused for exactly the reason the
original target is. And a snapshot lives *inside* the pool, so it is
reachable only once that pool is exported, which is the same condition
again.

`llapi_scan_device.3` had it right all along, listing under `-EBUSY`
"imported by this or another host, or left dirty by a crash ... export
it first". So the two pages contradicted each other, and the one a user
reads first was the wrong one.

Corrected to say the one thing that is true: **exporting the pool is the
only way in**, and a snapshot becomes reachable at the same moment.

### And the same claim one entry up

The reviewer also caught that `--device`'s "This always works" is no
longer true once 68163 adds ZFS to that entry. Checked the series
position: at **68160** the entry reads "A block device, disk image or
snapshot" with no ZFS at all, so it is accurate there — 68163 is what
adds the ZFS clause and therefore what owes the caveat. Both fixes land
in 68163, not 68160.

`--device` now separates the two: nothing has to be mounted and no
module loaded, which holds unconditionally for ldiskfs; a ZFS dataset
has the one more condition, named.

## Not new: 68159 and 68160's janitor reports

All classified. 56El (fixed locally), `racer`/`replay-dual` timeouts,
`sanity-pcc` 1c/1d, `recovery-small` 24b/155, and
`sanity-quota` test_80 — which the Janitor's own line lists as seen in
**76 other reviews**, from 68374 back to 32038.

## Verification

`groff -ww` clean; `checkpatch-man` 1 warning, **the same one before and
after** (a pre-existing short-option header). checkpatch 0 errors.
Builds under `-Werror`. 18 changes, 18 Change-Ids.
