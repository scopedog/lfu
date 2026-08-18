# Draft ticket: reimplement `lfs find` on the namespace scanner API

**Status:** draft, not filed. The consumer half of LU-20462's first step
(2026-08-18 meeting: *replacing `lfs find` on the client side*). Depends on
**LU-20603**, the scanner API ([`llapi-scan-api.md`](llapi-scan-api.md)).

**File** linked to **LU-20462** and to **LU-20603**. Type Technical task ·
Components utils.

---

## Summary

lfs: reimplement `lfs find` on the namespace scanner API

## Description

`lfs find` becomes the first consumer of the client-side scanner API: its output
path is reimplemented to consume per-object records rather than to walk and
print in one pass. Behaviour is preserved.

Two reasons this is the right first consumer, beyond the HLD naming it:

- It is the honest test of the record. If `lfs find` can be rebuilt on the API
  without special cases, the record carries what a consumer needs; if it cannot,
  the record is wrong, and it is much cheaper to learn that here than after a
  wire format is frozen around it.
- It avoids leaving `lfs find` as technical debt — the alternative is LFU
  shipping beside a `lfs find` that still does its own traversal forever.

**Regression net.** The `sanity.sh` 56\* series is a substantial existing test
suite for `lfs find` semantics. Keeping it green is the acceptance criterion,
and being obliged to keep it green is the point.

**Known piece of work, from the LU-20603 lab.** A regular file's record carries
neither `LLAPI_SCAN_SIZE` nor `LLAPI_SCAN_BLOCKS`: the data is on OSTs and the
MDT's statx has no authoritative size, so the mask reports "cannot answer"
rather than zero. `lfs find` handles this today by testing `OBD_MD_FLSIZE` /
`OBD_MD_FLLAZYSIZE` and falling back to a `stat()` glimpse. `--size`, `--blocks`
and `--lazy` therefore need that fallback carried over explicitly rather than
inherited — it is the one place where consuming records instead of walking and
testing in one pass changes what the code has to do.

**Scope boundary.** Filter evaluation stays where it is for this patch: the goal
is a behaviour-preserving change of internals. Pushing the filter down into the
scanner, with the I/O cost tiers, is separate work and a separate ticket.

### Why separate from the API ticket

The API is a component with several queued consumers; this is one of them, and
the one most likely to attract argument about user-visible behaviour. Separating
them means a behaviour question here cannot hold up the API that PCC-RO, Trash
Can and the resync tools are waiting on.

Push both as **one stacked Gerrit series** even so, so reviewers see the API and
its caller together.

---

## Before pushing to Gerrit

- [ ] Branch off a fresh `origin/master`. The `lustre-release` working tree
      currently carries unrelated modifications (`sanity.sh`,
      `sanity-selinux.sh`, untracked `lustre/utils/selinux/`) on the LU-20551
      branch — none of it belongs in this push.
- [ ] Subjects `LU-20603 llapi: ...` and `LU-YYYYY lfs: ...`, each with
      `Signed-off-by:` and the `Change-Id:` the `commit-msg` hook generates.
- [ ] `Test-Parameters:` covering the `sanity.sh` 56\* series.
- [ ] `git push review HEAD:refs/for/master`.
