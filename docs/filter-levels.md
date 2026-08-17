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
**bold** = not implemented in the scanner named by that column; see §5.

**Status, 2026-08-17.** All three scanners now implement every predicate in
this table except the tier-3 depth pair. The device backends got it in the
morning (`src/lfu_filter.{c,h}`, 43 cases in `tests/run_tests.sh`); the OSD
scanner got it in the afternoon, as **filter pushdown**: the same evaluator
compiled into the `lfu_ring` kernel module and applied to each object between
`rec()` and the ring, with the three tier-0 fields added to both OSD read paths
and a `rec(DORA_XATTR)` extension that serves tier 1 out of the mapped
inode-table block (§5.4). The bold markers below are left as written so the
table still records what was missing when the analysis was done; §5 says what
each one is now. **The kernel side is written and reviewed but has not been
built or run against a lab MDT** — see §5.4 for exactly what is and is not
verified.

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
| `--stripe-count -c` `--stripe-size -S` | **1** | **1** | **1** | `trusted.lov` |
| `--ost -O` `--stripe-index -i` `--pool` | **1** | **1** | **1** | `trusted.lov` — resolvable from the MDT, **no OST scan needed**. `-i` and `-O` are **one predicate**, not two: `lfs.c:7804` handles `case 'i': case 'O':` in the same block, so both mean "has an object on any of these indices" |
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

### 5.1 OSD scanner — three free tier-0 predicates missing (closed 2026-08-17)

`osd_raw_attr()` filled nine fields — mode, nlink, uid, gid, size, blocks,
atime, mtime, ctime — and the iget-based `DOIF_ATTR` path the same nine, which
is why the `attrsum` checksums matched between them. Missing from both:

| was missing | field | needed by |
|---|---|---|
| `la_btime` | `i_crtime`, `i_crtime_extra` | `--btime/--crtime` + 8 `--newerXY` forms |
| `la_projid` | `i_projid` | `--projid` |
| `la_flags` | `i_flags` | `--attrs` |

All three are in the same inode record — free — and the ZFS OSD path already
filled them, so this was an ldiskfs-only asymmetry.

**Closed.** `patches/itable-blockparse-v2_17_55.patch` now fills all twelve on
both paths, kept field-for-field identical so `attrsum` still matches:
`la_btime` from `i_crtime` plus its epoch bits, guarded on `i_extra_isize`
reaching the field exactly as the device scanner does; `la_projid` guarded the
same way and on the `project` feature; and `la_flags` composed the way
`osd_inode_getattr()` composes it — `i_flags & LUSTRE_FL_USER_VISIBLE`, plus
the orphan/encrypted bits from the LMA via `lma_to_lustre_flags()`. On the iget
path the LMA-derived bits are added only when the LMA in `oti_ost_attrs` is
provably this object's (its FID equals the returned one), because
`osd_get_lma()` leaves that buffer untouched when there is no LMA.
`tests/blockparse_test.sh` lifts the raw parser out of the patch and checks the
three new fields against `debugfs stat` on inodes it set them on — 106 checks,
at both 256- and 1024-byte inode sizes.

### 5.2 Device scanners — closed, 2026-08-17

This section described the largest gap in the filter story: both backends
parsed exactly one xattr, `trusted.lma`, so no layout, pool, name or size
predicate was implementable on either, and `struct lfu_rec` had no `flags`
field so `--attrs` was missing too. Three of 34 predicates worked.

**All of it is now implemented for both device backends.** The shape follows
§9 rather than bolting more options onto the core:

| piece | where |
|---|---|
| predicate compiler, demand mask, tier-0/tier-1 evaluation, `lfs find` argument grammar | `src/lfu_filter.c`, `src/lfu_filter.h` |
| on-disk SOM / LOV v1+v3+composite / LMV structures, with `_Static_assert` on every size | `src/lfu_lustre.h` |
| xattr fetch per demand mask, external-block accounting | `lfu_read_xattrs()` in `src/lfu_scan_ldiskfs.c` |
| the same, from the already-unpacked DXATTR nvlist | `lfu_zfs_read_obj()` in `src/lfu_scan_zfs.c` |
| `rec.flags` for `--attrs` | `i_flags` on ldiskfs; `lfu_zfs_attrs()` converts `z_pflags` as `attrs_zfs2fs()` does |

Everything in the §3 table is implemented on both device backends except the
tier-3 depth pair, which a flat scan cannot answer at all. 43 new cases in
`tests/run_tests.sh` cover it (61 total, from 18), including the §4 size trap
and the §4.4 undecided outcome, all green under ASan+UBSan.

Three decisions were forced along the way, none of them cosmetic:

1. **`--blocks` means what `lfs find` means**, so the old behaviour needed a
   new name: `--dev-blocks` is the target's own allocation — `i_blocks` on
   ldiskfs, `doi_physical_blocks_512` on ZFS — and `--blocks` is the file's,
   resolved per §4. `-b/--blocks-gt` compiles to `--dev-blocks`, unchanged, so
   the LUG slide-21 command still runs and now means what it says. This settles
   the §6 "three numbers, one predicate name" question for two of the three;
   OST-actual still needs an OST scan.
2. **Both quantities compare in bytes.** `lfs find` multiplies `stx_blocks` by
   512 before comparing (`liblustreapi_pfind.c:2971`) and treats a bare number
   as 512-byte units, so `--blocks +1G` is "more than 1 GiB allocated". The
   unit multiplier doubles as the equality margin, exactly as `find_value_cmp()`
   has it, so `--size 1M` means "up to 1 MiB" here too.
3. **A backend refuses what it cannot answer.** `lfu_target_ops` grew
   `can_supply`, `attr_mask` and `missing_fields`; a filter needing an xattr or
   field the backend has no access to is rejected at parse time. The kernel-ring
   backend (`lfind-kmdt`) therefore refuses every tier-1 predicate and also
   `--btime`, `--projid` and `--attrs`, because the ring record carries only the
   nine fields `osd_raw_attr()` fills — §5.1's gap seen from the consumer end.
   ZFS refuses `--attrs Compressed` and `--attrs Encrypted`: `z_pflags` has no
   per-file bit for either. "No matches" and "not supported" must not look alike.

**Correction to this document's own reading of linkea.** `src/lfu_lustre.h` said
`leh_magic`/`leh_len` were big-endian. They are not: `linkea_init()` writes the
header in the *writing host's* order (`linkea.c:23`) and a reader detects a
foreign order by comparing the magic against its own swab (`linkea.c:38-41`).
Only `lee_reclen` is genuinely big-endian, byte by byte (`linkea.c:97`).
`--name` matched nothing until the reader was changed to do what the kernel
does. Anything else in this tree that reads linkea should be checked.

### 5.3 The xattr walkers are already generic

- **OSD**: `osd_raw_lma()` walked the in-inode xattr area with a name match on
  `("trusted","lma")`. **Done:** it is now a wrapper over `osd_raw_xattr(sb,
  raw, index, name, nlen, &val, &vlen)`, the generic lookup, which returns a
  pointer into the mapped block — no copy, no I/O. `rec(DORA_XATTR)` calls it
  for whatever the filter demands (§5.4).
- **ldiskfs device**: `ext2fs_xattrs_read_inode()` parses from the inode buffer
  already held, and `ext2fs_xattr_get(h, key, ...)` fetches by name. Design
  question **M9 is answered: `read_inode()` does follow `i_file_acl`** (measured
  2026-08-17 — `design-ldiskfs-scanner.md` §6.1). Tier 1 is therefore free *and*
  correct for spilled objects, and the hand-rolled inline parser is not needed.
  The sting in the tail: there is no inline-only request in the API, so the
  extra block read is invisible from outside libext2fs and the tier-2 *cost*
  can only be inferred from `i_file_acl` plus the demand mask, never counted
  directly.
- **ZFS device**: one `nvlist_unpack` of `SA_ZPL_DXATTR` already yields **every**
  Lustre xattr; only the LMA lookup is wired up. Adding SOM/LOV/linkea is
  `nvlist_lookup_byte_array()` calls against an nvlist already in hand — free.

### 5.4 Filter pushdown on the OSD scanner — the shape, and what is verified

Design-osd-scanner.md §4 asked for the filter to evaluate **in kernel,
immediately after `rec()`, before the record enters the ring**, cost-ordered,
bounded and non-allocating, with the filter program as UAPI. That is what
landed, in four pieces:

| piece | where | what |
|---|---|---|
| the evaluator, built twice | `src/lfu_filter_eval.c` + `src/lfu_filter.h` | the parser (`lfu_filter.c`, lfs find syntax → `struct lfu_filter`) stays userspace; the evaluator is one source, linked into the device scanners and `#include`d into the kernel module. `lfu_filter.h` has a kernel branch: `<linux/glob.h>`'s `glob_match()` for `fnmatch()`, the on-disk structures from `<uapi/linux/lustre/lustre_idl.h>` instead of `lfu_lustre.h`, no libc |
| tier 1 through the iterator | `patches/otable-xattr-v2_17_55.patch` | `rec(DORA_XATTR)` returns one named xattr of the current object: from the in-inode area of the block a block-parsing iterator still holds (tier 1, no I/O), else via a live inode and `__osd_xattr_get()` (tier 2 if the raw inode had `i_file_acl`, counted as such); "not in the inode and no external block" is a free, definite `-ENODATA`. `rec(DORA_STATS)` reads back the iterator's counters: raw vs `-EAGAIN` fallback (queue item 4), and where every xattr came from. **osd-zfs (added 2026-08-17, later in the day):** the same two requests, served from the `SA_ZPL_DXATTR` nvlist `it::next` already unpacks to find the LMA and now keeps until the next `next()` (tier 1, no I/O, no second dnode hold), else from the xattr directory through `__osd_xattr_get_large()` (tier 2, counted); "not in the SA area and no xattr directory" is the free `-ENODATA`. Only alongside `DOIF_ATTR`, which is when the SA handle is open long enough to read `SA_ZPL_XATTR`. Written and applied clean; **not yet built or run on a lab** |
| the producer as filter | `src/kernel/lfu_ring.c` | `SET_FILTER` ioctl takes `struct lfu_filter` (fixed-size POD, magic+version+size checked, every index range-checked by `lfu_filter_validate()` before use); per object: `rec(DORA_ATTR)` → `lfu_filter_tier0()` → only if it survives and the demand mask is non-empty, `rec(DORA_XATTR)` per demanded xattr into scratch allocated once at open → `lfu_filter_tier1()`. NOMATCH never touches the ring; UNKNOWN is counted and enters only with `LFU_FILTER_EMIT_UNKNOWN`. `INFO` reports what the OSD under the module can serve; `STATS` returns every counter at EOF. The producer now uses a `DOIF_PARALLEL` private iterator by default, so it is on the block-parse path |
| the consumer | `src/lfu_scan_kmdt.c` | compiles the filter, negotiates via `INFO` (wire version 2 with `btime`/`projid`/`flags`, LMA flags, and the decoded SOM/LOV/LMV values riding along so `size=` prints the file's size), sends it, and sets `lfu_target_ops.pushdown` so the core neither prefilters nor re-runs tier 1; the kernel's per-tier counts are folded into the ordinary summary, and tier 2 is printed as a rate over the objects tier 1 examined |

Two design points worth stating because they were forced rather than chosen:

- **The xattr fetch had to go through the iterator.** A producer above the OSD
  can only reach an object by `dt_locate()`, which is an OI lookup and an
  `iget` — the two things block parsing removed. `rec(DORA_XATTR)` is the only
  place the mapped block is still in hand, so that is where tier 1 has to be
  served, and the tier-2 fallback there is `osd_iget()` +
  `__osd_xattr_get()`, exactly the path a spilled LMA already takes.
- **The evaluator is now under kernel constraints everywhere.** No allocation,
  no recursion, no libc, `-std=gnu89` (a RHEL 9 kernel's dialect: no `for (int
  i…)`), and `struct lfu_filter`'s layout is a wire contract
  (`_Static_assert`ed at 32 × 352 + 16 bytes). Those constraints apply to the
  userspace scanners too now, since it is one source — which is the point.

**What is verified, and how far:**

| claim | how | status |
|---|---|---|
| the raw parser fills btime/projid/flags correctly and `osd_raw_xattr()` finds inline SOM/LOV and refuses to invent a spilled one | code lifted verbatim from the patch, run against `mke2fs`/`debugfs` images | **106 checks pass** (`tests/blockparse_test.sh`) |
| the evaluator makes the same decisions along its kernel branch as its userspace one, on the same bytes, and matches this document's tables | compiled twice (`-std=gnu89 -DLFU_KERNEL_TEST` with `tests/kstubs/` for the four kernel headers) | **47 cases, identical** (`tests/filter_eval_test.sh`) |
| the kernel branch of the evaluator uses no libc beyond `mem*` | `nm -u` on the object | passes |
| every Lustre identifier the evaluator uses exists in the real `lustre_idl.h`/`lustre_user.h` | grep against v2_17_55 | all resolve |
| the six-patch stack applies cleanly on v2_17_55 | `git apply` on a fresh worktree | clean |
| `lfu_ring.c` and the two OSD patches **compile and run** | GCP lab, Rocky 9.8, Lustre v2_17_55 + the stack, single node, 302,122 objects | **done 2026-08-17** — [`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md) |
| every predicate agrees with the userspace device scanner on the same device | 12 filters, FID sets compared | **all AGREE** |
| `--dev-blocks +1G` matches nothing and `--blocks +1G` finds the 1.5 GiB file | the §4.3 prediction, on a real MDT | **reproduced** |

**Built and run 2026-08-17** —
[`filter-pushdown-measured-2026-08-17.md`](filter-pushdown-measured-2026-08-17.md).
The stack compiles, `lfu_ring.ko` carries the evaluator, every predicate agrees
with the userspace scanner on the same device, tier 2 fired once and was counted,
and a rejecting tier-0 filter turns out to be **8% faster than no filter at
all** because a rejected object never enters the ring. Two reporting bugs
surfaced and are fixed (`--limit` mid-batch, and a rate line that divided
survivors by wall time). Still warm-only, single-threaded, ldiskfs-only.

**Lab checklist, when one is next up** (same recipe as
`parallel-osd-scanner-2026-08-15.md` §"Nothing here has been compiled"; the
stack order matters — `rec-attr-zfs` must precede `parallel-it`, which touches
`osd-zfs/osd_internal.h` after it):

```sh
# in the lustre-release checkout at v2_17_55, on the lab
for p in rec-attr rec-attr-zfs parallel-it itable-readahead \
         itable-blockparse otable-xattr; do
	git apply lfu/patches/$p-v2_17_55.patch || exit 1
done
make -j$(nproc)
cp lustre/osd-ldiskfs/osd_ldiskfs.ko /lib/modules/$(uname -r)/extra/lustre/fs/ && depmod -a
# unmount, rmmod osd_ldiskfs, remount; then:
modinfo osd_ldiskfs | grep -q lfu_blockparse && echo patched

# the ring module (needs CONFIG_GLOB=y: grep GLOB /boot/config-$(uname -r))
cd lfu/src/kernel
make -C /lib/modules/$(uname -r)/build M=$PWD LUS=/root/lustre-release \
     KBUILD_EXTRA_SYMBOLS=/root/lustre-release/Module.symvers modules
insmod lfu_ring.ko dev=lustre-MDT0000-osd

# the consumer, built anywhere: first a plain stream, then the filters
cd lfu && make kmdt
build/lfind-kmdt -q /dev/lfu_scan                       # INFO line, counts
build/lfind-kmdt -q --type f --mtime +30d /dev/lfu_scan  # tier 0 in kernel
build/lfind-kmdt -q --blocks +1G /dev/lfu_scan          # tier 1: SOM via DORA_XATTR
build/lfind-kmdt -q --pool fast --stripe-count +1 /dev/lfu_scan
build/lfind-kmdt -q -u --size +0 /dev/lfu_scan          # the undecided population
```

The three things to look at in the summary: `filtered (t0)`/`(t1)` (the
kernel did the work), `xattr: inline=… external=… iget=…` (tier 1 was served
from the block, and how often it was not), and `fallback=` (queue item 4, the
`-EAGAIN` rate). Then the same filter through `lfind-ldiskfs` on the
unmounted device should give the same emitted set.

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
at **0.0%** of runtime. The OSD scanner now leans on exactly this: its
iterator has to unpack that nvlist to find the LMA anyway, so keeping it one
call longer makes `rec(DORA_XATTR)` a lookup in memory (§5.4) — the ZFS analogue
of reading the in-inode area out of the mapped block on ldiskfs, and cheaper,
because there is no name-index walk. The tier-ordered prefilter is kept there for *semantic
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
  Rule module design. *(2026-08-17: it now has one — `lfu_field_tier()`, and
  the demand mask is what the kernel producer uses to decide which
  `rec(DORA_XATTR)` calls to make at all.)*

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

- ~~**The OSD-side filter has not run.**~~ **Run 2026-08-17** (§5.4). What is
  still unmeasured there: cold, parallel enumeration into one ring, and ZFS.
  `bench_osd_sweep.sh`'s warm rows should also be re-taken with a tier-1 filter
  set, which is now possible.
- **The tier-2 rate on a realistic filesystem** (§7). The two numbers we have
  are both ~0 on lab targets with default striping. Note that M9's answer
  changes how this has to be measured on ldiskfs: since libext2fs fetches the
  external block transparently, the rate is now reported as "objects with an
  external block, under a filter that demanded a tier-1 xattr"
  (`tier-2 (read)`), and its *cost* has to come from timing a scan with and
  without a tier-1 predicate rather than from any counter.
- ~~**Design question M9**~~ — **answered 2026-08-17: it follows.** See §5.3.
- ~~**Whether `-blocks +1G` really matches nothing on a real MDT today**~~
  (§4.3) — **reproduced 2026-08-17 on a real MDT**: `--dev-blocks +1G` found 0
  of 302,122 objects, `--blocks +1G` found the 1.5 GiB 4-stripe file, FID and
  size matching `lfs path2fid`/`stat` exactly. The synthetic fixture in
  `tests/mkimage.sh` stays as the regression test.
- ~~**Which `--blocks` LFU means**~~ — **decided** (§5.2): `--blocks` is the
  file's, `--dev-blocks` is the target's. OST-actual remains out of reach
  without an OST scan.
- **Linkea completeness for `--name`** — maintained, but not verified in this
  project as reliable enough to answer `-name` without the namespace. `--name`
  is now implemented and tested against a linkea we wrote; what is untested is
  whether a real MDT's linkea holds every name for every object. (Its byte
  order, at least, is now right — see §5.2.)
- **How "unknown" is represented** — and how often it happens. Measured
  2026-08-17: **zero** undecided objects on a v2_17_55 MDT, because SOM is on by
  default (there is no `mdt.*.enable_som` any more) and every closed file has
  `trusted.som`. The third outcome is still real for a file open for write, but
  it is rare, which is better for the largest-files use case than §4 assumed.
  As for the representation, it now has *an* answer, not necessarily the right
  one: undecided objects are counted on their own summary line and
  suppressed from the output, and `-u/--emit-unknown` emits them tagged
  `+unknown`. What is unsettled is whether a consumer wants that as a third
  output stream, an exit status, or a per-record field — and what the aggregation
  operators (`largest`, `histogram`) should do with an unknown size, since
  "skip it" and "count it as zero" give different answers to the same question.
