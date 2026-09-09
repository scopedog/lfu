# `lfs find` on an offloaded scan — what has to change

**Date:** 2026-09-09 · **Status:** design proposal, v0.1 · **For:** LU-20721
**Parent:** [`design-osd-port.md`](design-osd-port.md) §4 ·
**Depends on:** [`design-lfs-find-on-scan.md`](design-lfs-find-on-scan.md), the
2.18 split that made a second object source possible

Asked after the scope was settled: does `lfs find` itself need redesigning to
sit on an offloaded scan? **Mostly no, in one place emphatically yes.**

---

## 1. What does not need redesigning

The predicate machinery already generalises, which was the point of LU-20605
and LU-20611. `find_prefilter()`, `find_want()` and `find_decide()` sit behind
`struct find_ctx`, which already copes with the three things an offloaded scan
needs: `fc_path == NULL` when no namespace was walked, `fc_p`/`fc_d`/`fc_fdp`
absent when there are no descriptors, and `fc_mnt_fd` to resolve a FID against a
mount or print the FID.

So the client-side half of the HLD's *"partially on the server with Filters on
the client"* — applying the residue — is `find_decide()` over records. That is
literally what `llapi_find_device()` does today. It is built and shipped.

The filter compilation vocabulary is shared already, and the record is the
record. None of that moves.

## 2. Scope is the real problem

**A scan enumerates a target. `lfs find` takes a subtree.**

```
lfs find /mnt/lustre            -size +1G     offload is a clear win
lfs find /mnt/lustre/home/alice -size +1G     offload enumerates everything
                                              and discards almost all of it
```

Nothing today expresses "scan only this subtree" to a scanner: `lfsp_search` is
ZFS vdev directories and `lfsp_max_depth` bounds a walk. A target scan is
whole-target by construction, and a subtree is a namespace concept the object
table does not carry.

Three ways out:

| | |
|---|---|
| **(a) Server-side ancestry filter** | The server has the linkea, so it *can* walk up to test ancestry. But that is per object and it is not cheap — a tier-2 predicate at best, defeating the cost-ordered reject that makes pushdown worth having |
| **(b) Client-side after resolution** | Resolve every FID to a path and match the prefix. Defeats the entire purpose for a narrow subtree |
| **(c) Offload only when it pays, walk otherwise** | Keeps both paths honest |

**Recommend (c)**, with (a) as a later refinement once there is a reason to
believe subtree scans at scale are a real workload.

That means `lfs find` needs an **offload decision rule**, and that is new work
with no counterpart in `lfind`.

### 2.1 The rule should be dull

The decision wants to turn on the ratio of subtree to filesystem, which the
client cannot know without doing the work. Every clever proxy is a guess, and a
wrong guess makes `lfs find` *slower than it is today* — a regression users
notice immediately and blame on the feature.

So, for v1:

- **offload when the argument is the filesystem root** — unambiguous win
- **offload when the user asks for it explicitly** — their judgement, not ours
- **otherwise walk**

Nothing adaptive. If evidence later shows a threshold worth having, add it with
the evidence.

## 3. Offload is a transparent optimisation, not a mode

This is the sharpest difference from `lfind` and it must not be blurred.

`lfind` **refuses** a predicate it cannot answer — that is correct there,
because the user chose a target scan. `lfs find` must **never** refuse
something it accepts today. Its semantics are fixed; offload is an
implementation detail that either applies or does not.

So it falls back to the walk when:

- a predicate describes a walk (`-maxdepth`, `-mindepth`)
- the connect flag is absent, or the server is too old
- per-scan negotiation answers "not at all"
- the scope rule above says no

And the constraint that shapes the implementation:

> **Once a record has been printed, there is no falling back.**

The decision must therefore be complete *before the first line of output*, and a
failure part-way through an offloaded scan is an **error**, not a silent switch
to walking — otherwise the user gets some objects twice and no indication. Same
discipline as the ring's gap marker: a consumer is always told when its view is
incomplete.

## 4. Merge across MDTs

N streams become one answer, and three things follow.

**Ordering changes.** Today output is traversal order, depth first. Offloaded it
is inode order, interleaved across MDTs. Nothing in find's contract promises an
order and `find(1)` does not either, but scripts assume things, so it belongs in
the manual page rather than in a surprise.

**Duplicates are unsolved.** A file being migrated can appear on two MDTs. The
client cannot hold four billion FIDs to deduplicate, so this needs a rule rather
than a data structure. Candidates, none chosen:

- the server marks objects under migration and the client drops one side
- deduplicate only within a bounded window, accepting that a slow migration can
  still produce two lines
- accept duplicates and document them

**This is the question for Andreas**, unanswered in every HLD revision, and it
gates the merge.

**Incompleteness must be loud.** If one MDT fails mid-scan the answer is short.
That has to be an error with a named target, never a quietly truncated listing —
the same failure that made "never drop a record silently" the rule for the ring.

## 5. Proposed shape

```
llapi_find(path, param)
      |
      +-- find_offload_decide(path, param)      <- NEW
      |        no  -> llapi_find_with_cb(...)   <- today's walk, untouched
      |        yes -> llapi_find_offload(...)   <- NEW
      |
llapi_find_offload()
      negotiate           connect flag; per scan: entire / partial / none
      compile filter      existing vocabulary
      determine residue   find_want() over what the server accepted
      issue N scans       one per MDT, in parallel
      merge + dedupe      <- NEW, and the duplicate rule is unsettled
      find_decide()       existing, per record
      resolve FID->path   existing, via fc_mnt_fd
      print               existing
```

**Two boxes are genuinely new**: the decision and the merge. Everything else is
already in the tree, which is the dividend from having split find's predicates
from find's traversal in 2.18.

## 6. What this adds to LU-20721

To scope:

- the offload decision rule (§2.1) and the fallback discipline (§3)
- the merge, its ordering note, and its incompleteness rule (§4)

To open questions:

- **subtree scope** — how, or whether, a scan can be confined to a subtree.
  This is new; it was not in the ticket and is not in the HLD
- duplicates across merged streams, already listed, now with the reason it
  cannot be solved by deduplicating everything

To the manual page: that output order is unspecified when the search is
offloaded.
