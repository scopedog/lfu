# `llapi_scan()` — one door, and the source chosen per question

**Date:** 2026-09-10 · **Status:** design proposal, v0.1 · **For:** LU-20721
**Depends on:** [`design-lfs-find-offload.md`](design-lfs-find-offload.md)
(the scope rule and the fallback discipline), the two-node measurement in
`bench-data/2026-09-10/rpc-two-node.txt`
**Prerequisite already shipped:** raw `trusted.link` across the ring
(2026-09-10), without which the two sources could never answer the same
question

---

## 0. The question

> If `llapi_scan_mount()` is faster than `llapi_scan_namespace()`, users will
> not find it necessary to use `llapi_scan_namespace()`. So we probably need a
> function like `llapi_scan()` that calls either one.

**Agreed — and the reasoning generalises past the case that prompted it.** But
the premise needs one correction first, because it decides what the dispatcher
can be.

## 1. "Faster" is not a property of the source

It is a property of *(source, query)*.

```
llapi_scan("/mnt/lustre",             ...)   offload: 30x
llapi_scan("/mnt/lustre/home/alice",  ...)   offload: enumerates the whole
                                             MDT and discards nearly all of it
```

A target scan is whole-target by construction: the otable iterator walks the
inode table and has no notion of a subtree. So on a filesystem of a billion
objects, offloading `find /mnt/lustre/home/alice/tmp` is not a 30x win, it is
a catastrophic loss — and a user notices a regression far faster than they
notice a speedup.

So the dispatcher's job is **not** "pick the faster source". It is:

> **pick the cheapest source that can answer *this* question.**

That is a different function, it needs inputs the caller already has, and it
is the reason the decision belongs in the API rather than in each consumer.

`design-lfs-find-offload.md` §2.1 already reached this conclusion for `lfs
find` and settled on a deliberately dull rule. This design puts the same rule
one layer down, where every consumer gets it.

## 2. What the two sources actually differ in

Measured today on the same filesystem, same predicate (`-mtime -1 -type f`,
88k objects):

| | `llapi_scan_namespace()` | `llapi_scan_mount()` (offloaded) |
|---|---|---|
| walks | a mounted namespace, from any directory | whole MDTs |
| answer | **87,944** | 87,958 raw / **87,946** classified |
| `lfsr_path` | the path as walked | NULL — a target holds names, not paths |
| `lfsr_name` | from the dirent | from `trusted.link` (shipped 2026-09-10) |
| `lfsr_fd`, `lfsr_parent_fd` | open descriptors | none |
| view | live, through the MDS | on disk; can lag by tens of seconds |
| order | traversal, depth first | inode order, interleaved across MDTs |
| privilege | POSIX, what the caller can read | `CAP_SYS_ADMIN`, bypasses POSIX |
| cost | proportional to the **subtree** | proportional to the **filesystem** |
| round trips | 88,028 | 20 |

Two of those rows are the whole design problem: **the answers differ**, and
**the cost scales with different things**.

## 3. Answer-equivalence is a prerequisite, not a detail

A dispatcher that silently swaps two sources returning different sets is a
wrong-answer generator, and a plausible one — the counts are within 0.02% of
each other. So `llapi_scan()` may only choose freely where the sources are
made to agree:

- **the visible set.** The offload must apply the same classifier the walk
  implies. It already can: that is the difference between `lfind --target`
  (87,946) and `--internal` (87,958). The residue against the walk's 87,944 is
  two nameless MDT objects a walk cannot reach, and a caller asking for paths
  drops them anyway.
- **names and paths.** Until this morning the offload could answer neither, so
  it could not have substituted for a walk at all. Raw `trusted.link` in the
  record tail changes that: a path is reconstructible from linkea plus the
  directory map, which `LU-20637` already builds for `--paths`.
- **what is still missing** must be reported, not hidden. `lfsp_got` already
  exists for exactly this: it reports the answered subset of `lfsp_want`.

**Testable, and it is the same oracle used all day:** run both sources over
one filesystem, compare record for record. Anything else is an assertion.

## 4. What cannot be equalised, and therefore must be asked about

**Staleness.** The on-disk view can lag the live one by tens of seconds — the
HLD says so in *Inconsistencies in Scanning Results*, and it is inherent, not
a bug to fix. A caller that needs a coherent view must be able to demand one.

**Ordering.** Traversal order versus inode order interleaved across MDTs.
Nothing promises an order, `find(1)` does not either, but scripts assume, so
it belongs in the manual page rather than in a surprise.

**Privilege.** The offload is admin-only and bypasses POSIX checks; the HLD is
explicit that the failure mode there is a *disclosure*, not a wrong answer. A
non-privileged caller therefore walks — which needs no special case, since it
is also the fallback.

## 5. The decision rule

Deliberately dull, following `design-lfs-find-offload.md` §2.1. In order:

| # | test | if it fails |
|---|---|---|
| 1 | caller pinned a source (`lfsp_source`) | honour it, or `-ENOTSUP` if impossible |
| 2 | `LLAPI_SCAN_F_COHERENT` not set | walk |
| 3 | caller has `CAP_SYS_ADMIN` | walk |
| 4 | server, module and backend all present | walk |
| 5 | `lfsp_want` ⊆ what a target scan answers | walk |
| 6 | **the start point is the mount root** | walk |
| 7 | — | **offload** |

Rule 6 is the scope rule, and it stays dull on purpose: the decision wants the
ratio of subtree to filesystem, the client cannot know it without doing the
work, and every clever proxy is a guess whose wrong half is a visible
regression. A caller who knows better says so (rule 1). If evidence later
justifies a threshold, it arrives **with the evidence**; the HLD's *Persistent
Aggregates* are the thing that would eventually supply it.

### 5.1 Why rule 6 cannot become a ratio test

The obvious objection to rule 6 is that it throws away the offload for
`lfs find /mnt/lustre/some/dir`, which is most of what people actually type.
So: can a target scan be restricted to a subtree, and if it can, does rule 6
become a threshold on the ratio?

**It can be restricted. It cannot be made to cost what the subtree costs.**

#### Membership is discovered by reading the object

A target scan walks the object table in **inode order**, which has no
relationship to the directory hierarchy. The thing that says whether an object
belongs to a subtree — its parent FID, in `trusted.link` — lives *on the
object itself*.

So membership is discovered by reading the object, and therefore cannot be
used to avoid reading it. There is no seek-to-subtree, and no way to prove an
unread inode is absent from the tree without reading it. ldiskfs's Orlov
allocator does give a subtree partial inode-number locality, but locality is
not a bound: skipping on it would silently drop objects, and a scan that is
sometimes incomplete is worse than one that is honestly slow.

This also disposes of the "enumerate the subtree first, then skip the rest"
shape — `scandir()` over the subtree, feed the OSD scanner the inode set. To
enumerate the subtree you must walk the namespace, and walking the namespace
*is* `llapi_scan_namespace()`, the cost the offload exists to avoid. Having
paid it, you would then still walk the whole inode table to find what you
listed.

The narrower version is not silly and still loses: `readdir` is batched and
cheap while `stat` is a round trip per file, so "readdir for FIDs, attributes
from the target" has a real shape. But turning a FID into attributes is an OI
lookup plus `iget` per object — the random-access path
`osd-ldiskfs: read the inode table, not the inodes` deliberately removed. It
trades O(filesystem) sequential reads for O(subtree) random ones, and
sequential wins until the subtree is very small — by which point rule 6 has
already said *walk*.

#### What restriction is actually worth, and what it costs

The walk is the cheap half. The expensive half is the **per-object work**: the
tier-1 xattr reads and the linkea tail. Measured on the 09-09 fixture, 88k
files on one MDT: 263,939 xattr reads at ~136 ns each for attributes and LMA,
rising to 351,896 once names cross. A subtree filter that rejects early skips
all of that, and skips the record, the ring bytes and the RPC with it.

The machinery is mostly built. `scan_dirmap_prepass()` already constructs
FID → (parent, name) for **every directory** on the target, in a
directory-only pass chosen precisely because "a filesystem holds far fewer
directories than files". Subtree restriction is then a predicate over an index
that already exists:

1. directory-only prepass — already written, already used by `--paths`
2. walk up from the start directory's FID, marking the directory FIDs beneath it
3. main pass emits only objects whose parent FID is in that set

Note the filter would begin in userspace. The pushdown work landed on the
device scanner; `lfu.ko` has none yet — *"No filter yet: every object is
emitted and the consumer decides."* Pushing a subtree predicate down to the
OSD is what converts "fewer records" into "fewer reads", and it is the step
that makes this worth doing at all.

#### The consequence for rule 6

Cost becomes **O(filesystem) walk + O(subtree) output**. Never O(subtree).

So restriction *narrows* the region where the walk wins without closing it: a
small directory on a large filesystem still belongs to
`llapi_scan_namespace()`, because the offload still reads every inode on every
MDT to find it. The crossover moves; the crossover still exists; and the
client still cannot know the ratio without doing the work — which is the whole
reason rule 6 is a scope test and not a threshold.

**Rule 6 therefore stands.** What subtree restriction buys is not a change to
the decision rule but a cheaper *right-hand side* once the rule has already
said offload, and a caller who pins the source under rule 1 gets a far better
deal than they do today.

#### Measured (2026-09-10)

Built on the client as described above — directory-only pre-pass, then a
search pass filtered on the parent's membership, memoised per directory —
and measured on two nodes, one MDT, 88k files, `-mtime -30 -type f`, caches
dropped on both, median of five. Raw data and method in
`bench-data/2026-09-10/subtree-two-node.txt`.

| scope | share | stock `lfs find` | offload | |
|---|---|---|---|---|
| `/` | 100% | 8.955 s | **0.291 s** | 30.8× |
| `bench` | 99.9% | 8.919 s | 0.412 s | 21.6× |
| `bench/d3` | 11.4% | 2.510 s | 0.405 s | 6.2× |
| `d0` | 0.06% | **0.035 s** | 0.404 s | walk 11× faster |

Walk and offload agree as FID sets on every subtree, diff 0 both ways.

**The prediction held exactly.** A subtree offload costs the same ~0.405 s
whether it returns 87,894 files or 50: the root's 0.291 s plus the pre-pass
(+0.12 s, about 40%), and twice the round trips (42–44 against 21). O(filesystem)
read plus O(subtree) output.

**The crossover is a fraction of the filesystem, not a file count.** The
offload pays ~4.6 µs per object on the MDT; the walk 102–251 µs per file under
the directory. They meet when the subtree holds roughly **2–5% of the
filesystem** — about 1,600–4,000 files here. Interpolated between `d0` and
`d3`, not measured. A real network raises the walk's per-file cost and lowers
that fraction, but cannot remove it.

**So rule 6 stands, now with a number behind it.** The decision needs the
subtree's share of the filesystem, and the client cannot know that share
without counting — which is the walk. Rule 1 lets a caller who knows say so.

And one lesson for anyone re-measuring: `-type f` alone is answered from the
directory entry, so stock `lfs find` does it as a readdir (0.172 s cold for
88k files) with no per-object request at all. A predicate the dirent answers
is never worth offloading, at any scope — which belongs in the decision rule
as surely as scope does.

#### One cheap win that is separable

On DNE the dirmap says which MDTs actually hold directories of the subtree, so
`llapi_scan_mount()` can **skip whole MDTs**. That is O(1) to decide once the
prepass has run, and on a many-MDT filesystem it removes a large fraction of
the work rather than a large fraction of the records. It is worth doing
independently of the rest of this section.

True O(subtree) needs a parent → children index maintained across scans — the
scanner-as-index-builder idea, and a different project from this one.

**The decision must complete before the first record is delivered.** Once a
record has been handed to the callback there is no falling back: a failure
part-way through an offloaded scan is an error, never a silent restart as a
walk, or the consumer sees some objects twice and is told nothing.

## 6. Shape

```c
int llapi_scan(const char *path, const struct llapi_scan_param *sp,
               llapi_scan_cb_t cb, void *data);
```

**The same signature as `llapi_scan_namespace()`**, so it is a drop-in and so
the scope rule can compare `path` against its mount root.

Appended to `struct llapi_scan_param` — appended, per the rule that struct
now states and that today's field-order fix restored:

```c
__u32  lfsp_source;   /* in: 0 auto, or pin a source */
```

Reported back through `struct llapi_scan_stats`, which the caller already owns
and the scan already fills, and which negotiates its own size through
`ss_size`:

```c
__u32  ss_source;     /* out: which source actually ran */
```

New flags:

```c
#define LLAPI_SCAN_F_COHERENT  /* a live view; never an on-disk one */
```

`ss_source` matters more than it looks: without it a caller cannot tell which
source answered, so cannot explain a result, and **a test cannot pin what it
is testing**.

### 6.1 The three doors stay

`llapi_scan()` is the front door; `llapi_scan_namespace()` and
`llapi_scan_mount()` remain, and are not deprecated:

- a consumer that **must** have descriptors or a live view says so directly
  rather than through a flag that means the same thing;
- the oracle needs to run both sources over one filesystem;
- the HLD's own model is pluggable *Input Scanner Modules*, with the front
  door selecting among them — not one module absorbing the others.

## 7. Where the decision belongs

`design-lfs-find-offload.md` §5 puts `find_offload_decide()` inside
`llapi_find()`. With `llapi_scan()`, most of that decision moves down a layer
and only the part that is genuinely about *predicates* stays up:

```
lfs find                          translates predicates into requirements:
   -maxdepth / -mindepth  ->        needs a walk (a depth is a walk concept)
   -printf %p, -name      ->        needs lfsr_path / lfsr_name
   default                ->        no constraint
        |
        v
llapi_scan(path, sp)              chooses the source (rules in §5)
        |
        +--> llapi_scan_namespace()
        +--> llapi_scan_mount()  -> one scan_dev per MDT, merged
```

This is the better factoring, and the reason is the question that prompted the
design: `lfs find` is *one* consumer. RobinHood, PoliMor, GUFI and the HLD's
other *Consumer Plugins* face the identical choice, and none of them should
each reinvent rule 6.

## 8. `llapi_scan_mount()` underneath

Still to build, and unchanged from what the board already records: one
`scan_dev` per MDT (the core carries one target, one label and one `tt_index`
per scan), `llapi_get_obd_count(mnt, &n, 1)` to enumerate, `lfsr_mdt_index`
already in the record to say which MDT answered.

**Duplicates across merged streams remain unsolved** — a file mid-migration can
exist on two MDTs, the client cannot hold four billion FIDs to deduplicate,
and this is the question for Andreas that every HLD revision has left open. It
does not block `llapi_scan()`: v1 delivers records per MDT with
`lfsr_mdt_index` set, so a duplicate is *visible to the caller* rather than
silently merged away. That converts an unresolved design question into a
stated contract instead of a latent wrong answer.

## 9. Phasing

| phase | offload used when | needs |
|---|---|---|
| **1** | root, admin, ldiskfs MDTs, no path demanded | `llapi_scan_mount()`, rules 1–6 |
| **2** | + paths demanded | linkea path reconstruction (linkea is shipped; the dirmap exists in LU-20637) |
| **3** | + subtrees | subtree restriction (§5.1) **and** a cost estimate — HLD *Persistent Aggregates*. Restriction alone does not unlock this: it makes the offload cheaper, not O(subtree), so the ratio still decides. |
| **4** | + non-privileged callers | server-side permission filtering; HLD defers this explicitly |

Phase 1 is worth having on its own: `lfs find /mnt/lustre -mtime -1` is the
common administrative case, and it is the one measured at 30x.

**Separable from the phases:** skipping whole MDTs that hold no directory of
the subtree (§5.1) needs only the dirmap and helps every DNE filesystem. It
belongs with phase 2, where the dirmap arrives anyway.

**Order:** the osd-zfs half of `DORA_LFU`/`DOIF_INDEX` comes first. Until it
lands, an MDT on ZFS answers `-EOPNOTSUPP` through this path, and the first
thing anyone tries should not be a coin flip on backend.

## 10. Open questions

1. **Duplicates across MDTs** (§8) — for Andreas; gates the merge, not this.
2. **Does `LLAPI_SCAN_F_COHERENT` default on or off?** Off is faster and
   matches `find(1)`, which promises nothing about concurrent modification.
   On is safer for a caller who did not think about it. This proposal says
   **off**, on the grounds that a scan of a live filesystem is inherently a
   moving target whichever source runs, and the HLD says the same.
3. **Should rule 6 accept "root of a fileset"** as well as the mount root, for
   nodemap-confined clients? Probably, but it needs the fileset root to be
   knowable client-side.
4. **Ordering in the manual page** — unspecified when offloaded; needs wording,
   not a decision.
5. **Is subtree restriction (§5.1) worth building before the cost estimate
   exists?** It cannot relax rule 6 on its own, so its only beneficiary today
   is a caller who pins the source under rule 1 — which is `lfind`, and which
   is a real user. Against that: a subtree predicate is most of the work of a
   general OSD-side filter pushdown, and `lfu.ko` has no filter at all yet, so
   building it for subtrees alone would be building the mechanism twice.
   Leaning towards **filter pushdown first, subtree as its first predicate**.
   *Update 2026-09-10:* the client-side restriction was built anyway, to
   measure §5.1, and it is useful to `lfind` today; pushdown remains what
   would turn fewer records into fewer reads.
6. **The walk branch must inherit `lfs find`'s parallelism.** Measured
   2026-09-10: `llapi_scan_namespace()` with its defaults took 21.4 s where
   `lfs find` took 9.0 s for the same 88k getattrs — the same opcode, the same
   count, no OST requests, and statahead ruled out. Stock ran ~3 requests at
   once; `lfsp_thread_count` defaults to the caller's own thread, so the scan
   ran one. `lfs find` picks 4 threads per MDT capped at half the CPUs. A
   `llapi_scan()` that walks with the scan's defaults would regress every
   subtree it keeps on the walk — the very case rule 6 keeps there. Either
   the door picks find's default, or `lfsp_thread_count = 0` starts meaning
   "choose" rather than "one"; the second changes a published default.
7. **A predicate the directory entry answers is never worth offloading.**
   `-type f` alone is a readdir: 0.172 s cold for 88k files. Rule 5 checks
   that the target *can* answer; nothing yet checks whether the walk answers
   it without a per-object request, which decides it just as surely.
