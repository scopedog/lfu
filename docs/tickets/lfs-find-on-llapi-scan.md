# Draft ticket: reimplement `lfs find` on the namespace scanner API

**Status:** draft, not filed. The consumer half of LU-20462's first step
(*replacing `lfs find` on the client side*). Depends on **LU-20603**, the
scanner API ([`llapi-scan-api.md`](llapi-scan-api.md)).

**File** linked to **LU-20462** and to **LU-20603**. Type Technical task ·
Components utils.

---

## Summary

lfs: reimplement `lfs find` on the namespace scanner API

## Description

`lfs find` becomes the first consumer of `llapi_scan_namespace()` (LU-20603):
its output path consumes per-object records instead of walking and printing in
one pass. Behaviour is preserved.

It is the honest test of the record. If `lfs find` rebuilds on the API without
special cases, the record carries what a consumer needs; if it does not, the
record is wrong, and that is far cheaper to learn now than after a wire format
is frozen around it. It also stops `lfs find` becoming technical debt beside
LFU.

**Acceptance:** the `sanity.sh` 56\* series stays green.

**Known work, from the LU-20603 lab.** A regular file's record carries neither
`LLAPI_SCAN_SIZE` nor `LLAPI_SCAN_BLOCKS` — the data is on OSTs and the MDT's
statx has no authoritative size, so the mask reports "cannot answer" rather
than zero. `lfs find` copes today by testing `OBD_MD_FLSIZE` /
`OBD_MD_FLLAZYSIZE` and falling back to a `stat()` glimpse. `--size`,
`--blocks` and `--lazy` need that fallback carried over explicitly; it is the
one thing consuming records does not inherit for free.

**Scope:** a behaviour-preserving change of internals. Pushing the filter down
into the scanner, with its I/O cost tiers, is separate work.

**Review note:** pushed as one stacked Gerrit series with LU-20603, so the API
and its first caller are visible together.

---

## Before pushing to Gerrit

- [ ] Branch off a fresh `origin/master`; the main `lustre-release` tree
      carries unrelated LU-20551 work.
- [ ] Subjects `LU-20603 llapi: ...` and `LU-YYYYY lfs: ...`, each with
      `Signed-off-by:` and the hook's `Change-Id:`.
- [ ] `Test-Parameters:` covering the `sanity.sh` 56\* series.
- [ ] `git push review HEAD:refs/for/master`.

---

## Paste into Jira (wiki markup)

Jira renders wiki markup, not Markdown: {{*bold*}} is single asterisks,
{{{{monospace}}}} replaces backticks, and a line *starting* with {{*}} becomes a
bullet — so emphasis at the start of a line uses an {{h5.}} heading instead.

```
{{lfs find}} becomes the first consumer of {{llapi_scan_namespace()}}
(LU-20603): its output path consumes per-object records instead of walking
and printing in one pass.  Behaviour is preserved.

It is the honest test of the record.  If {{lfs find}} rebuilds on the API
without special cases, the record carries what a consumer needs; if it does
not, the record is wrong, and that is far cheaper to learn now than after a
wire format is frozen around it.  It also stops {{lfs find}} becoming
technical debt beside LFU.

h5. Acceptance
The {{sanity.sh}} 56* series stays green.

h5. Known work, from the LU-20603 lab
A regular file's record carries neither {{LLAPI_SCAN_SIZE}} nor
{{LLAPI_SCAN_BLOCKS}} -- the data is on OSTs and the MDT's statx has no
authoritative size, so the mask reports "cannot answer" rather than zero.
{{lfs find}} copes today by testing {{OBD_MD_FLSIZE}} /
{{OBD_MD_FLLAZYSIZE}} and falling back to a {{stat()}} glimpse.  {{--size}},
{{--blocks}} and {{--lazy}} need that fallback carried over explicitly; it is
the one thing consuming records does not inherit for free.

h5. Scope
A behaviour-preserving change of internals.  Pushing the filter down into the
scanner, with its I/O cost tiers, is separate work.

h5. Review note
Pushed as one stacked Gerrit series with LU-20603, so the API and its first
caller are visible together.
```
