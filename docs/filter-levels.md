# Filter Items and Where Each One Is Evaluated — All Three Scanners

**Date:** 2026-08-16
**Status:** design analysis. Every "where the data lives" claim is read out of
`lustre-release` at `v2_17_0` or out of this repo's own source and is cited.
Cost claims are inferences from
[`blockparse-2026-08-16.md`](blockparse-2026-08-16.md) and the tier-2 counters
already in the device scanner, and are marked as such.
**Answers:** "we know the items we filter on — at which level do we filter
each?", for the OSD scanner and for both device-scanner backends.

LFU replaces `lfs find`, so the filter vocabulary is **closed and known before
the scan starts**. The planner can therefore compute the attribute demand set
up front and tell the scanner how far into each object to decode. A scan for
`-mtime +30 -uid 1000` should never touch the xattr area.

Two steps: (1) enumerate the items, (2) assign each one a tier, per scanner.

---

## 1. Vocabulary — one model, not three

`design-ldiskfs-scanner.md` §6 already defines the cost tiers, and §7 the
evaluation rule. That model is the right one and this document uses it
throughout rather than inventing a second naming scheme:

| Tier | Cost | Contents |
|---|---|---|
| **0** | free — already in the buffer the scan is reading | raw inode / SA bonus fields |
| **1** | free — an **inline** xattr in the same record | `trusted.lma`, `.lov`, `.som`, `.link`, `.lmv`, small user xattrs |
| **2** | **one extra random read** — external EA block (`i_file_acl`) / SA spill block | large layouts, long linkea, big user xattrs |
| **2b** | **an entire extra inode read** — `ea_inode` | xattrs exceeding one block; the feature *is* enabled on real MDTs (§4 below) |
| **3** | not answerable by the scanner | pathname, depth, OST state, cross-MDT composition |

§7's rule — *evaluate in ascending tier, never take a tier-2 read for an object
already rejected at tier 0* — is implemented in the device scanner today as
`lfu_prefilter()` (`src/lfu_scan.h:163`), called before the LMA parse on ldiskfs
and before the DXATTR unpack on ZFS.

The tier boundary that matters is **1→2**, not 0→1. `mkfs.lustre` sizes MDT
inodes precisely so LMA, LOV, SOM and linkea fit *inside* them —
`libmount_utils_ldiskfs.c:860-890` enumerates exactly those four EAs in its
budget, and picks 1024 B for ≤16 stripes, 2048 B for 17–59, and **512 B above
59 stripes because past that the layout is going external anyway** (bz 7241).

---

## 2. The items

From the `lfs find` option table and usage string (`lfs.c:473-505`): **34
predicates**, once the 20-member `--newerXY` matrix collapses into one. All are
`(field, op, value)` with uniform `!` negation and `+`/`-` comparison, so
evaluation is one switch — no dynamic dispatch per object.

Not filters, listed so the accounting is complete: `--lazy|-l`, `--skip|-k`,
`--threads`, `--print|-P`, `--print0|-0`, `--printf`, `--help|-h`.

---

## 3. Assignment

`OSD` = in-kernel OSD scanner (`DOIF_PARALLEL` + block parse).
`ldiskfs` / `ZFS` = the two userspace device-scanner backends.
**bold** = not implemented today; see §5.

| predicate | OSD | ldiskfs dev | ZFS dev | source |
|---|---|---|---|---|
| `--atime -A` `--mtime -M` `--ctime -C` | 0 | 0 | 0 | `i_[amc]time` (+ epoch bits in `i_*_extra`) / `SA_ZPL_[AMC]TIME` |
| `--btime -B` `--crtime` | **0** | 0 | 0 | `i_crtime` / `SA_ZPL_CRTIME` |
| all 20 `--newerXY` | 0/**0** | 0 | 0 | same fields; reference file resolves to a timestamp at *parse* time |
| `--uid -u` `--user -U` `--gid -g` `--group -G` | 0 | 0 | 0 | `i_uid`/`i_gid` + `l_i_*_high` / `SA_ZPL_UID`/`GID` |
| `--type -t` `--perm` | 0 | 0 | 0 | `i_mode` / `SA_ZPL_MODE` |
| `--links` | 0 | 0 | 0 | `i_links_count` / `SA_ZPL_LINKS` |
| `--projid` | **0** | 0 | 0 | `i_projid` / `SA_ZPL_PROJID` |
| `--attrs` | **0** | **0** | 0 | `i_flags` / `SA_ZPL_FLAGS` |
| `--mdt-index -m` *(files)* | 0 | 0 | 0 | not stored — it is *which target you are scanning* |
| `--size -s` `--blocks -b` | **1** | **1** | **1** | `trusted.som`, **not** `i_size`/`SA_ZPL_SIZE` — see §4 |
| `--stripe-count -c` `--stripe-index -i` `--stripe-size -S` | **1** | **1** | **1** | `trusted.lov` |
| `--ost -O` `--pool` | **1** | **1** | **1** | `trusted.lov` — resolvable from the MDT, **no OST scan needed** |
| `--layout -L` (`released`/`raid0`/`mdt`) | **1** | **1** | **1** | `trusted.lov` |
| `--comp-*`, `--mirror-count -N`, `--mirror-state`, `--ext-size -z` | **1** | **1** | **1** | composite `trusted.lov` — bigger, spills sooner |
| `--foreign` | **1** | **1** | **1** | `trusted.lov`/`.lmv` magic |
| `--name -n` | **1** | **1** | **1** | `trusted.link` (name + parent FID per link) |
| `--mdt-count -T` `--mdt-hash -H` *(dirs)* | **1** | **1** | **1** | `trusted.lmv` |
| `--xattr` | **1/2** | **1/2** | **1** | arbitrary xattr regexp; on ZFS one unpack has them all (§6) |
| `--maxdepth -D` `--mindepth -d` | 3 | 3 | 3 | depth is a property of the tree; a flat scan has none |

**No predicate is inherently tier 2.** Every tier-1 predicate *becomes* tier 2
when its xattr spills, which is **data-dependent, not query-dependent** — wide
striping, composite layouts, many hardlinks, large user xattrs. That reframes
the open question: the thing to measure is the spill *rate* per filesystem
shape (§7), not a per-predicate verdict.

---

## 4. The size trap — the one item where the obvious answer is wrong

This matters because "largest files" is a headline use case: `largest`,
`smallest` and `histogram` are in the LUG aggregation operator list, and it is
the whole premise of the largest/newest-file index idea.

**An MDT inode's `i_size` is not the file's size.** For a regular file with OST
objects the MDT inode's size is stale or zero and `i_blocks` counts only the
*MDT inode's own* blocks — EA blocks and dirdata, single digits. The data, and
therefore the size, is on the OSTs. The same is true of `SA_ZPL_SIZE` on a ZFS
MDT.

`lfs find` knows this. From `liblustreapi_pfind.c:2862-2875`:

```c
if (param->fp_check_size &&
    ((S_ISREG(lmd->lmd_stx.stx_mode) && stripe_count) ||
      S_ISDIR(lmd->lmd_stx.stx_mode)) &&
    !(flags & OBD_MD_FLSIZE ||
      (param->fp_lazy && flags & OBD_MD_FLLAZYSIZE)))
        decision = 0;      /* -> fall through to a full stat, which glimpses */
```

And the MDT decides which flag it can set (`mdt_handler.c:874-904`):

| case | size valid on the MDT? |
|---|---|
| not a regular file (dirs, symlinks) | yes — `OBD_MD_FLSIZE` |
| regular file with **no** OST objects (incl. DoM) | yes — `OBD_MD_FLSIZE` |
| HSM-**released** | yes, the MDT holds the size |
| **strict SOM** enabled | yes — `OBD_MD_FLSIZE` |
| **lazy SOM** present (`MA_SOM`) | yes, but `OBD_MD_FLLAZYSIZE`, and the value is `ma->ma_som.ms_size` — **the `trusted.som` xattr, not `i_size`** |
| otherwise | **no** — the client must glimpse the OSTs |

Four consequences, all three scanners:

1. **`--size`/`--blocks` are tier 1, not tier 0.** The number to read is
   `struct lustre_som_attrs { __u16 lsa_valid; __u16 lsa_reserved[3]; __u64
   lsa_size; __u64 lsa_blocks; }` (`lustre_user.h:557`) out of `trusted.som` —
   24 bytes, and one of the four EAs `mkfs.lustre` sizes the inode for, so
   inline in the normal case.
2. **`design-ldiskfs-scanner.md` §6 has two errors.** Its tier table lists
   `size, blocks` under tier 0, and lists SOM under **tier 2**. Both are wrong:
   the tier-0 entries are the wrong numbers for striped files, and SOM is in the
   `mkfs.lustre` inline budget (`24(lustre_som_attrs) + 16(xattr_entry) +
   4("som")`), i.e. tier 1.
3. **The LUG slide-21 flagship example is not all-tier-0.**
   `lfs find /lfs02 -atime +30d -blocks +1G -projid 1999` is cited in §7 as the
   intended fast path because "all three predicates are tier 0". `-blocks +1G`
   is not. Against a real MDT the device scanner today compares `i_blocks`,
   which for a striped regular file is ~0 — so the filter would match nothing.
   The example is tier 0 × 2 + tier 1, and it is still a good fast-path example,
   just not the one currently described. *Predicted from the code path above,
   not yet reproduced on a real MDT — see §7.*
4. **An MDT-only scan implements `lfs find --lazy` semantics, exactly.** That is
   not a limitation to apologise for; it is a named, supported mode of the
   command being replaced. LFU should say so, and should flag or refuse
   non-lazy `--size` rather than silently answer a different question. And
   because SOM is written on close, a size filter has a **third outcome besides
   match and no-match: unknown** — files never closed since SOM was enabled, and
   files currently open for write, have no `trusted.som`.

---

## 5. Implementation gaps, per scanner

### 5.1 OSD scanner — three free tier-0 predicates missing

`osd_raw_attr()` fills nine fields — mode, nlink, uid, gid, size, blocks,
atime, mtime, ctime (`patches/itable-blockparse-v2_17_55.patch`). The
iget-based `DOIF_ATTR` path fills the same nine
(`patches/rec-attr-v2_17_55.patch:91-102`), which is why the `attrsum`
checksums match between them.

| missing | field | needed by |
|---|---|---|
| `la_btime` | `i_crtime`, `i_crtime_extra` | `--btime/--crtime` + 8 `--newerXY` forms |
| `la_projid` | `i_projid` | `--projid` |
| `la_flags` | `i_flags` | `--attrs` |

All three are in the same inode record — free. **The ZFS OSD path already fills
all three** (`SA_ZPL_CRTIME`, `SA_ZPL_FLAGS`, `SA_ZPL_PROJID` in
`patches/rec-attr-zfs-v2_17_55.patch:134-179`), so this is an ldiskfs-only gap
and a backend asymmetry that will bite the first time a filter is written
against ZFS and then run on ldiskfs.

**The ldiskfs *device* scanner already reads crtime and projid**
(`src/lfu_scan_ldiskfs.c:91-104`), guarded on `i_extra_isize` reaching the
field. The in-kernel path can copy that logic directly.

### 5.2 Device scanners — no tier 1 at all beyond LMA

Both backends parse exactly one xattr: `trusted.lma`, for the FID
(`lfu_scan_ldiskfs.c:141`, `lfu_scan_zfs.c:305`). `XATTR_NAME_LOV`, `_LMV`,
`_LINK`, `_HSM`, `_SOM` are all defined in `src/lfu_lustre.h:22-28` and none is
read. So today **no layout, pool, name or size predicate is implementable on
either device backend** — that is the single largest gap in the filter story,
and it is the same gap on all three scanners.

`struct lfu_rec` (`src/lfu_scan.h:50-64`) has no `flags` field either, so
`--attrs` is missing on the device scanners too, even though §6 lists it at
tier 0.

Implemented filters today: `--atime`, `--blocks`, `--projid` — three of 34,
chosen to match the LUG slide-21 example, and `--blocks` is the one §4 says is
reading the wrong number.

### 5.3 The xattr walkers are already generic

- **OSD**: `osd_raw_lma()` walks the in-inode xattr area with a name match on
  `("trusted","lma")`. Extending to `som`, `lov`, `link`, `lmv` is a change to
  the name comparison plus a per-xattr decoder — no new mechanism, no new I/O.
- **ldiskfs device**: `ext2fs_xattrs_read_inode()` parses from the inode buffer
  already held, and `ext2fs_xattr_get(h, key, ...)` fetches by name. Design
  question **M9** — whether `read_inode()` also follows `i_file_acl` to the
  external block — is still open and decides whether tier 1 stays free for
  spilled objects or the inline region must be parsed by hand
  (`design-ldiskfs-scanner.md` §6.1). The OSD block parser has already written
  that hand-rolled inline parser, so if M9 comes out badly the code exists.
- **ZFS device**: one `nvlist_unpack` of `SA_ZPL_DXATTR` already yields **every**
  Lustre xattr; only the LMA lookup is wired up. Adding SOM/LOV/linkea is
  `nvlist_lookup_byte_array()` calls against an nvlist already in hand — free.

---

## 6. ZFS has almost no tier-1/tier-2 cliff

This is the sharpest difference between the backends, and it cuts the opposite
way from the usual ZFS story.

On ldiskfs, each xattr is a separate entry that individually fits or spills. On
ZFS, **all Lustre xattrs live in one `SA_ZPL_DXATTR` nvlist** in the dnode's SA
bonus buffer, and one unpack yields all of them
(`design-zfs-scanner.md` §4.3). Measured on a real MDT (§15 of that doc):

- **max bonus 636 B** of ~832 B available in a 1 KiB dnode
- **1 spill block in 1351 objects** — 0.074%

So on ZFS, tier 1 is genuinely the same read as tier 0, and the unpack profiled
at **0.0%** of runtime. The tier-ordered prefilter is kept there for *semantic
parity* with ldiskfs, not for speed (`design-common-core.md`, and the comment at
`src/lfu_scan_zfs.c:266-270`).

Consequence for the filter compiler: **the tier model is ldiskfs-shaped.** A
compiler that sorts predicates by tier must not be *wrong* on ZFS, but it is
mostly not doing anything there. Conversely a filter that is unusable on
ldiskfs — xattr regexp, wide-striped pool matching — may be perfectly cheap on
ZFS. Any statement of the form "filter X does not meet the target" needs a
backend attached to it.

### `--blocks` does not mean the same thing on the two backends

- ldiskfs: `i_blocks`, 512-B units, allocated blocks.
- ZFS: `doi_physical_blocks_512` — **post-compression physical**
  (`src/lfu_scan_zfs.c:256-258`, design §12).

Already flagged as a record-format issue; as a *filter* it is worse, because
`-blocks +1G` then returns different sets for the same logical data. And per §4
neither is the file's OST block count. Three different numbers, one predicate
name — this needs deciding, not documenting.

---

## 7. Spill rates — what has actually been measured

The tier-2 rate is "the single number that predicts whether a given filter
meets the target on a given filesystem" (§6 of the ldiskfs design). The device
scanner already instruments it. What exists:

| target | tier-2 rate | source |
|---|---|---|
| lab MDT, 1024 B inodes, 12,001,264 in-use inodes | **0 (0.0%)** | `bench-data/2026-08-06/bench/b_idle1.out:20` |
| real MDT (ZFS), 1351 objects | **1 spill block (0.074%)** | `design-zfs-scanner.md` §15 |

Both are lab filesystems with default striping and short filenames, so they are
a **lower bound, not a general answer**. What is missing is the rate on a
composite-layout or wide-striped filesystem, which is where the tier model
predicts it goes to ~100%. Note also that the real MDT has `ea_inode` enabled
(`features: uninit_bg ea_inode dirdata project`, same bench output), so tier 2b
is reachable in production, not theoretical.

The OSD scanner can produce the same number for free: `osd_iit_iget_raw()`
already returns `-EAGAIN` when the in-inode LMA is absent — which is exactly the
external-EA case — and the caller falls back. Counting that fallback gives the
in-kernel tier-2 rate with no new mechanism.

---

## 8. Tier 3 differs by scanner, and the device scanner cannot reach it

| tier-3 item | OSD scanner | device scanner |
|---|---|---|
| non-lazy `--size`/`--blocks` | conceivable — runs inside a live server that could glimpse — but a per-object RPC is not a scan | **impossible**: unmounted device or snapshot, no client, no MDT service, no network |
| pathname | Output Format concern, priced separately | same, and the device scanner is better placed: it reads *every* object anyway, so it can build the parent-FID → name map offline from linkea |
| `--maxdepth`/`--mindepth` | needs the tree | same, but likewise buildable offline from a full scan |
| cross-MDT composition | the shards live on other MDTs | same |

The one exception worth recording: the device scanner **can** scan OST targets
(device role detection, `design-ldiskfs-scanner.md` §5.1), so OST object sizes
are reachable in principle — but joining them to MDT FIDs via each OST object's
`trusted.fid` is a second full scan plus a join, which is what LFSCK does. That
is a legitimate design option for exact sizes, and it is nothing like a filter
predicate. Price it as its own mode.

---

## 9. Recommended shape

Compile the filter into a **demand mask** at parse time and pass it into the
scanner the way `DOIF_ATTR` is passed today, and the way `lfu_prefilter()`
already consumes tier-0 options:

```
NEEDS_INODE    — always
NEEDS_SOM      — size/blocks predicates
NEEDS_LOV      — stripe/pool/ost/layout/comp/mirror predicates
NEEDS_LINKEA   — name predicate
NEEDS_XATTR    — arbitrary xattr regexp
NEEDS_EXTERNAL — set per object at runtime, when any of the above missed inline
NEEDS_TREE     — depth predicates; rejected by both scanners
```

- **A pure-tier-0 query never opens the xattr area.** `-mtime +30 -uid 1000
  -type f` should run at the full block-parse rate. (`-size` is not pure tier 0
  — see §4.)
- **Tier 2 becomes a visible, countable event** rather than an unexplained
  slowdown. Both scanners can already detect it per object; report it.
- **The fallback already exists on both.** `osd_iit_iget_raw()` returns
  `-EAGAIN` and the caller repeats through `osd_iit_iget()`; the device scanner
  has `i_file_acl != 0` testable with no extra I/O. Tier 2 is therefore not new
  code so much as a decision about *when* to take the existing slow path — and
  whether to defer it to a second pass instead of taking it inline.
- **§7's ordering rule needs a tier from the filter API.** A filter presented as
  an opaque match function forfeits all of this; worth stating in the Filter
  Rule module design.

**Sharding constraint on aggregations.** Filters that aggregate rather than
select — `count`, `sum`, `histogram`, `largest`/`smallest N`, `min`/`max` — must
accumulate per shard/chunk and merge at the end, the way `fidsum`/`attrsum` and
`struct lfu_stats` already do. Commutative merges are trivial; `largest N` needs
a per-worker bounded heap. An aggregation that is not associative does not
shard and should be rejected at parse time rather than silently serialising the
scan.

**`--skip PERCENT` falls out of chunking for free** on both scanners — sampling
*n*% of the chunks is a cursor change, not a per-object test.

---

## 10. What is not settled

- **The tier-2 rate on a realistic filesystem** (§7). The two numbers we have
  are both ~0 on lab targets with default striping.
- **Design question M9** — whether `ext2fs_xattrs_read_inode()` follows
  `i_file_acl`. Decides whether tier 1 is free for spilled objects on the
  ldiskfs device backend.
- **Whether `-blocks +1G` really matches nothing on a real MDT today** (§4.3).
  The mechanism is clear from `mdt_handler.c`, but the `lfs find` oracle test
  (§17) compared FID *sets* only, and `tests/run_tests.sh:78` exercises
  `--blocks` against a synthetic image with no striped files. One run against
  the benchfs MDT settles it.
- **Which `--blocks` LFU means** across ldiskfs / ZFS / OST-actual (§6).
- **Linkea completeness for `--name`** — maintained, but not verified in this
  project as reliable enough to answer `-name` without the namespace.
- **How "unknown" is represented.** SOM-less files under a size filter, and
  objects the block parser fell back on, are neither matches nor non-matches.
  The output format has no representation for that yet.
