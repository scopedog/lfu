# 68156 `edaaad1a` — an unreadable inode at a chunk boundary counted twice

2026-09-08, fourth of the seventeen. **Verified, fixed, and measured on a real
device: unfixed 8 of 270 skipped, fixed 4 of 266 — exactly double, in both
counters.**

## The claim

`scan_ldiskfs_chunk()`'s skip arm `continue`d without passing the
`ino > end_ino` test below it, so an unreadable inode just above the chunk
boundary was consumed by this chunk and read again by the chunk that starts at
`end_ino + 1`. `scan_sink_skip()` raises both `ss_seen` and `ss_skipped` for
`SKIP_IO`, so both overstated. Nothing is delivered twice — the bound still
guards every inode that reaches the sink.

## The one thing that had to be checked first

The fix reads `ino` on an error path, so it is only correct if libext2fs sets
it there. It does — from `lib/ext2fs/inode.c`, `ext2fs_get_next_inode_full()`
assigns

    scan->current_inode++;
    *ino = scan->current_inode;

**after** every one of `EXT2_ET_INODE_CSUM_INVALID`,
`EXT2_ET_BAD_BLOCK_IN_INODE_TABLE` and `EXT2_ET_INODE_IS_GARBAGE` is assigned
to `retval`, and immediately before `return retval`. The earlier returns —
which do leave `*ino` untouched — are the ones the existing `if (err != 0)`
already turns into `-EIO`, so the order is safe.

## Also fixed, same three lines

A reserved inode that could **not** be read was counted as a skipped object,
where a readable one is `continue`d without being counted. `ino <
EXT2_FIRST_INODE()` is now asked on this path too. A bad inode-table block in
group 0 spans reserved and real inodes alike, so this was reachable by the
same fault as the boundary case.

## Measured

Fixture: a copy of the lab MDT (`ipg` 25000, 4 groups, inode size 1024). With
`SCAN_CHUNK_INODES` 65536 that is 3 groups per chunk, so chunk 0's `end_ino`
is **75000** and inode **75001** is the first inode of the next chunk. Three
of the four inodes in its block (24998, offset 0) overwritten with `0xFF`, so
`extent_head_looks_insane()` fires on three of four and libext2fs declares the
whole block bad.

| | ss_skipped | ss_seen |
|---|---|---|
| unfixed | 8 | 270 |
| fixed | 4 | 266 |

Four garbage inodes, counted once each after the fix and twice before.

## Two traps, both worth keeping

**`EXT2_ET_INODE_IS_GARBAGE` is unreachable as shipped, and that is a finding
of its own.** `check_inode_block_sanity()` returns immediately unless
`EXT2_SF_WARN_GARBAGE_INODES` is set, and we set only
`EXT2_SF_SKIP_MISSING_ITABLE`. Proved with a standalone probe against the same
image: **flag off, libext2fs refuses nothing; flag on, it refuses exactly
75001–75004.** So the measurement above was taken with the flag set in a
throwaway build, and the flag is *not* in the commit — whether to ship it is
a real question with a cost, and is left for the user. See below.

**The ldiskfs backend is a dlopened plugin, and `PLUGIN_DIR` beats `$LUSTRE`.**
`libscan_ldiskfs.c` is **not** part of `liblustreapi.so` in this build
(`am__append_13` is commented out in the generated Makefile); it builds as
`scan_ldiskfs.so` and `scan_backend_load()` tries `PLUGIN_DIR/scan_ldiskfs.so`
*first*, falling back to `$LUSTRE/utils/` only if that fails. So
`make lfind` plus `LD_LIBRARY_PATH` — which is enough for anything in
`liblustreapi` — silently ran the **installed** backend, and three
measurements agreed with each other because none of them was testing the
build tree. The tell was `make liblustreapi.la` reporting "up to date" after
its `.lo` was deleted.

To test a backend change: `make libscan_ldiskfs.la`, move
`/usr/lib64/lustre/scan_ldiskfs.so` aside, and set `LUSTRE=<tree>/lustre`.
Put it back afterwards.

## Left for the user: should the garbage flag be set?

The scanner catches `EXT2_ET_INODE_IS_GARBAGE` and its comment says a body
"libext2fs calls garbage" is skipped — but the flag that makes libext2fs say
so is never set, so today such an inode is handed back intact and parsed as an
object. Setting `EXT2_SF_WARN_GARBAGE_INODES` would make the code do what it
says. Against it: `check_inode_block_sanity()` verifies a checksum and an
extent header for **every inode read**, on the hot path of a scanner measured
in millions of objects a second. That is a throughput question, not a
correctness one, and it wants its own measurement before it is decided.
