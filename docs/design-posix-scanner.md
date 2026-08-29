# The POSIX Input Scanner

**Date:** 2026-08-29 · **Module:** HLD *Client-Side changes → POSIX Input
Scanner* · **Status:** the honesty half is written and lab-verified, held
locally in 68094 · **Lab:** [`tests/lab-posix/`](../tests/lab-posix/)

The HLD names a POSIX Input Scanner beside the Lustre namespace scanner, for
PCC-RO and TCU: the same searches over a tree that is not Lustre.
[`architecture.md`](architecture.md) §7 already answered *how* — the walk has
carried a `statx`/`lstat` fallback since before this work, so

> the **POSIX Input Scanner is the same module with a different attribute
> source** … it should not be built twice.

So the module is not a crawler to write. It is a **contract to state and
enforce**: which fields a record carries when the attribute source is a stat
rather than an MDT, and — the part that was wrong — which it must not claim.

## 1. What it already did

`llapi_scan_namespace()` walks a non-Lustre tree today and returns 0. Measured
with [`tests/lab-posix/probe.c`](../tests/lab-posix/probe.c) rather than read
out of the code:

| | bits |
|---|---|
| answered | `TYPE MODE NLINK UID GID SIZE BLOCKS ATIME MTIME CTIME`, plus `PROJID` on demand where the filesystem has project quotas |
| absent, correctly | `LAYOUT LMV MDT_INDEX HSM` |
| absent, and answerable | `BTIME ATTRS` — the fallback uses `lstat`, which has neither |
| **wrong** | **`FID`** |

`lfs find` has worked off Lustre all along — `-type`, `-size`, `-mtime`, `-uid`
all answer correctly there — because `find_decide()` reads the same record.

## 2. The defect

A record off Lustre carried `LLAPI_SCAN_FID` set and a FID **built from the
object's filename**: `[0x61:0x0:0x0]` for `a`, `[0x676962:0x0:0x0]` for `big`.

The walk writes the name into `param->fp_lmd` because that buffer is the
ioctl's input as well as its output. The ioctl answers `ENOTTY`,
`convert_lmd_statx()` fills `lmd_stx` from `lstat` and leaves `lmd_fid` alone,
and `fid_is_sane()` accepts the leftover bytes as an **IGIF**. Nothing
downstream could catch it: an IGIF is a legitimate FID shape.

**The same defect was found and fixed one caller away, in the same change.**
`convert_lmdbuf_v1v2()` already carried `/* V1 put lmd_st where lmd_fid is:
those bytes are not a FID */`. The fix moves that clear **into
`convert_lmd_statx()`**, where the stat answer is built, so both callers are
covered and the V1 memset becomes redundant and goes.

**Why it is ours and not an upstream bug report.** Upstream nothing reads
`lmd_fid` for an object the ioctl did not answer for — `lfs find -printf %F`
calls `llapi_path2fid()` on the path. `llapi_scan_namespace()` is the first
consumer of that field, so the exposure arrives with 68094 and is fixed there,
before it lands.

## 3. What the module now promises

Stated in `llapi_scan_namespace.3` under *A target that is not Lustre*, and
enforced by `llapi_scan_test` **test10**, which builds a tree off Lustre and
asserts both halves — what a stat answers is present, and `FID`, `LAYOUT`,
`LMV`, `MDT_INDEX`, `HSM` are absent.

**test10 refuses to run on Lustre.** Every absence it checks would be present
there for a good reason, so a pass would mean nothing. `sanity` 157c passes
`-p $TMP`; `-p DIR` overrides when `P_tmpdir` is itself Lustre.

**Verified 2026-08-29:** all 11 `llapi_scan_test` cases pass, sanity 157c
passes twice, and the `nofid` arm — the clear cut back out — fails test10 with
`a record off Lustre carried a FID: valid=0x43ff`.

## 4. Is the `statx()` change necessary? No — checked against the HLD

The HLD names `statx()` for this module, which reads at first like a
requirement:

> **POSIX Input Scanner Module.** It *may be desirable* to also implement an
> Input Scanner Module that performs a traditional POSIX directory traversal
> for non-Lustre filesystems … This could likely be implemented as part of the
> Lustre Namespace Input Scanner module **using statx() calls to fetch file
> attributes from the kernel** rather than implementing a duplicate parallel
> namespace scanner module.

Read whole, the sentence's requirement is the *rather than* clause, and that is
the one we meet. Three things say `statx()` is a suggested route and not an
obligation:

1. **The module is outside the initial set.** *"The initial Input Scanner
   modules for locating files should be a Lustre client mountpoint scanner, an
   ldiskfs filesystem scanner, and Lustre Changelogs consumer."* POSIX is not
   among them, and its own section opens *"It may be desirable to also
   implement"*.
2. **`btime` is not one of the attributes the HLD asks for.** Its standard list
   is *"size, blocks, atime, mtime, ctime, etc."*
3. **The HLD explicitly allows omitting what is not available:** *"It should be
   possible to distinguish between required and optional attributes, allowing
   attributes to be returned if readily available … but omitting the pathname
   if not."* `sr_valid` is exactly that mechanism, so an absent `BTIME` is
   conformant rather than a gap.

**And the behaviour it would change is already deliberate and uniform.**
`find_decide()` has a case for a missing birth time, with the reason in the
code: an object with no `STATX_BTIME` cannot match `-btime`, so it does not
match and the walk carries on — *"ending it here, after matches have already
been printed, is the wrong answer, and on a walk the error reaches
llapi_semantic_traverse() and takes the whole subtree with it."*

That case is **not POSIX-specific**: an old ldiskfs inode whose `i_extra_isize`
does not reach `i_crtime` has no birth time either, and behaves identically on
Lustre. Measured: `lfs find /tmp/ptree -type f -btime -1d` returns nothing on a
tree created seconds earlier, and the same command on Lustre returns the file.
Adding `statx()` would fix the POSIX half of that asymmetry and leave the old
inode half exactly as it is — it moves the boundary rather than removing it.

**So: an enhancement, not a correctness fix.** What it would buy is `-btime`
and `--attrs` off Lustre on filesystems that have them (ext4, XFS; not tmpfs),
which is worth having on its own merits and worth its own patch. What it would
not buy is HLD conformance, which the contract in §3 already has.

**Nothing about the walk itself changed**, and nothing needs to: the traversal,
the thread pool and the predicates were already source-agnostic. That is the
architecture note's claim, now measured instead of assumed.
