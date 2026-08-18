# Upstream survey — what LFU can build on

Reference tree: `../lustre-release` @ `v2_17_55-2-gd717692511`.

The point of this doc is to separate *"LFU needs to invent this"* from *"this
already exists and needs exposing"*.

Written before the HLD (`reference/lfu-hld.pdf`) was available, so it reads the
tree kernel-first. The HLD's initial scanner is a **userspace libext2fs device
reader** that touches none of this. The findings below stay accurate and still
matter — they describe the *later* OSD API scanner path (`architecture.md` §6b)
and the client-side namespace scanner (§7) — but §1 is not the starting point.

## 1. The OSD scan engine already exists — it is just not reachable from userspace

`lustre/include/dt_object.h:370` declares `dt_otable_features`, a DT index
feature set that presents the OSD object table (ldiskfs inode table / ZFS dnode
range) as an ordinary `dt_it_ops` iterator. It is implemented by every OSD:

| OSD | Implementation |
|-----|----------------|
| ldiskfs | `lustre/osd-ldiskfs/osd_scrub.c:2760` (`osd_otable_it_init` … `osd_otable_it_next` at :2863) |
| ZFS | `lustre/osd-zfs/osd_scrub.c`, `osd-zfs/osd_index.c` |
| wbcfs | `lustre/osd-wbcfs/osd_object.c` |

Iteration is parameterised through the 32-bit `attr` argument of
`dt_it_ops::init()` — low 16 bits `enum dt_otable_it_valid`, high 16 bits
`enum dt_otable_it_flags` (`dt_object.h:1845-1876`). `DOIF_RESET` restarts at
the device beginning; `DOIF_DRYRUN` / `DOIV_DRYRUN` scan without repair —
already the semantics a read-only namespace scan wants.

The iterator supports **preload batching** (`osd_otable_it_preload`,
`osd_scrub.c:1193`) and coordinates with the background scrub thread via
`wait_var_event` (:2898), so it already handles the "scanner runs ahead of /
behind the consumer" flow-control problem.

**Today the only consumer is LFSCK** (`lustre/lfsck/lfsck_lib.c`). Nothing in
`lustre/utils/` or `lustre/include/uapi/` references `otable` — confirmed by
grep. So there is no userspace entry point at all.

> **Implication.** "Replaces OSD OI Scrub" is better read as *"promotes the OI
> scrub iterator into a first-class, generally-consumable scan primitive"* than
> as *"deletes OI scrub"*. The iterator is the asset; LFU's real work starts one
> layer up.
>
> The HLD confirms this: the OSD API Input Scanner "would re-use the OSD OI Scrub
> scanner, so optimizations in this code would benefit both LFU and LFSCK (which
> may itself be restructured into an Object Stream consumer)". Because all three
> OSDs already implement it, that module is mostly an exposure job.

## 2. Client-side parallel find already landed

`lustre/utils/liblustreapi_pfind.c` — 3759 lines, DDN / Patrick Farrell, 2024 —
implements a pthread worker pool over `llapi_semantic_traverse()`:

- `parallel_find()` (:3714) — entry point
- `work_unit_create_and_add()` (:3621), `cleanup_work_queue()` (:3654) — work queue
- `copy_find_param()` (:3357) — per-thread clone of the filter state
- `cb_find_init()` (:2413) — the actual per-file predicate evaluation
- `find_value_cmp()` (:500), `find_comp_end_cmp()` (:1004) — comparison primitives

This is the best available specification of **what a filter rule set has to
express**. `struct find_param` plus `cb_find_init()` is effectively the semantics
of `lfs find`; LFU's filter rules must be at least as expressive or `lfs find`
cannot be retargeted onto LFU without a behaviour change.

**Do not design the filter language from scratch — derive it from
`cb_find_init()`.**

The HLD says the same and goes further: this code is not just a reference, it is
the **source** of the client-side Lustre Namespace Input Scanner, to be extracted
from **LU-17814** and reworked to emit an Object Stream via
`ioctl(LL_IOC_MDC_GETINFO_V2)`. That module is step 2 of the build order and the
cheapest path to an end-to-end pipeline, since it needs no server changes at all.

`lfs find` itself dispatches at `lustre/utils/lfs.c:473` → `lfs_find()` (:7102).

## 3. Existing kernel→userspace channels, and why neither is sufficient

### Kernel comm (KUC)

`lustre/include/lustre_kernelcomm.h:210-221` — `libcfs_kkuc_group_add/rem/put/foreach`,
netlink-backed, group-addressed by `obd_uuid`. Used by HSM coordinator and
changelog.

### Changelog

`llapi_changelog_start/recv/fini/clear` (`include/lustre/lustreapi.h:708-724`),
kernel side in `lustre/mdd/mdd_changelog.c`, records persisted through llog.

Both are **record-at-a-time with a copy per record**. Neither is a zero-copy bulk
export.

Changelog is *not* something LFU escapes — the HLD keeps it as an Input Scanner
Module and adds an attribute-based Output Filter on the MDS. Its awkward
properties for enumeration still apply though: it is a change journal, not a
namespace listing; it needs a registered consumer before the events occur; and
unclaimed records pin llog space.

> **Implication.** Zero-copy bulk export is genuinely new to Lustre — but not new
> to Linux. The HLD names the kernel's **Circular Buffer Interface
> (`circ_buf.h`)** for the job, so this is an integration task, not an invention,
> and it is not needed until the OSD API scanner (build order step 6).

## 4. Serialization: nothing in tree

`grep -rli 'flatbuf|msgpack'` over the whole tree returns **zero** hits — no
source, no `configure.ac`/m4 probe. FlatBuffers (the HLD's front-runner) and
MessagePack are both new external build dependencies.

For the initial scanners this is ordinary userspace dependency work — the ldiskfs
device scanner and the client namespace scanner both run in userspace, where the
libraries exist.

It becomes hard at the OSD API scanner, which exports through `circ_buf` from
kernel context. Neither library ships a kernel-space encoder:

- **FlatBuffers** is C++ with a code generator; the C port (`flatcc`) has a
  runtime that would need porting and auditing for kernel use.
- **MessagePack** encoding is simple enough to hand-write in kernel, but then the
  "MessagePack" claim is really "a hand-rolled encoder that emits MessagePack
  framing".

Timing matters here: the format is frozen early (build order step 1), the kernel
encoder isn't needed until step 6. See [`open-questions.md`](../open-questions.md)
Kernel-side encoding — the question must be answered *before* the freeze.

## 5. Related subsystems LFU must not collide with

| Subsystem | Location | Relevance |
|-----------|----------|-----------|
| LFSCK | `lustre/lfsck/` | Current sole otable consumer; concurrent-scan and rate-limit interaction |
| OI scrub | `lustre/osd-ldiskfs/osd_scrub.c`, `osd_oi.c` | Owns the iterator and its checkpoint state |
| HSM | `liblustreapi_hsm.c`, `lhsmtool_posix.c`, `libhsm_scanner.c` | Named consumer (cap. 5); `libhsm_scanner.c` is a second existing scanner to reconcile |
| PCC | `liblustreapi_pcc.c` | Named consumer (PCC-RO) |
| FLR / mirrors | `liblustreapi_layout.c`, `liblustreapi_mirror.c` | Named consumer (resync); source of the "mirror status" index |
| linkea | `lustre/obdclass/linkea.c` | FID → pathname reconstruction; required to emit paths from a flat object scan |

`linkea` deserves a flag: a flat object-table scan yields FIDs, not paths. Every
consumer that wants a pathname forces a link-EA lookup and parent-chain walk.
The HLD settles the placement — FID→pathname is an **Output Format module**, and
pathname generation is explicitly excluded from the 1M obj/s/MDT target
(open-questions *Path resolution priced separately*). It remains the cost centre for access control (*Access control granularity*) and for
any filter that must touch a non-inline xattr (*Does the target survive real filters*).
