# LU-20603: client-side namespace scanner API in liblustreapi

**Filed 2026-08-18 as LU-20603** — Technical task, Open, linked to LU-20462 and
LU-17814. The reusable half of LU-20462's first step (*replacing `lfs find` on
the client side*); its first consumer is drafted in
[`lfs-find-on-llapi-scan.md`](lfs-find-on-llapi-scan.md) and **not yet filed**.

Kept here as the source text and the working checklist.

---

## Summary

llapi: namespace scanner API emitting per-object records to a consumer callback

## Description

LFU starts client-side so the record contents and the consumer API are settled
before any kernel or wire-protocol work is committed to.

Most of the crawler is already in tree: LU-17814 landed
`liblustreapi_pfind.c` — threaded traversal, attributes via
`LL_IOC_MDC_GETINFO_V2`, `statx()` fallback — and `llapi_find_with_cb()` /
`llapi_find_cb_t` are exported. This is not a new crawler, but a callback that
fills a per-object record instead of printing.

New `lustre/utils/liblustreapi_scan.c`:

```c
struct llapi_scan_rec;                  /* one object: FID, attrs, layout */
typedef int (*llapi_scan_cb_t)(const struct llapi_scan_rec *rec, void *data);

int llapi_scan_namespace(const char *path, struct llapi_scan_param *param,
			 llapi_scan_cb_t cb, void *data);
```

Exported by the existing `llapi_*` rule in `liblustreapi.map`; man page in
`Documentation/man3/`. Named for what it does rather than for the programme,
since renaming an exported symbol later is an ABI event.

Its own ticket because the scanner has several queued consumers — `lfs find`
first, then the PCC-RO and Trash Can cleanup tools, FLR/EC resync, HSM — and
each should be landable on its own.

**Scope:** this defines an in-memory record and a callback contract, **not** a
serialization. The Object Stream format is still open between FlatBuffers and
Cap'n Proto, so nothing here should freeze it.

**Review note:** pushed as one stacked Gerrit series with the `lfs find`
conversion (**LU-20605**), so the API's first caller is visible in the same
push.

---

## Before pushing — state as of 2026-08-18

- [x] `contrib/scripts/checkpatch.pl` clean on both patches, bar one advisory
      ("added file(s), does MAINTAINERS need updating?"). Fixing it took
      moving the `LLAPI_SCAN_*` comments above their `#define`s, shortening
      two struct comments, and reordering the man page's NOTES after ERRORS.
- [x] Builds under the tree's own `-Wall -Werror`; `sanity` 56\* identical
      before and after; ten lab checks green.
- [ ] **Nothing in-tree calls `llapi_scan_namespace()`.** LU-20605 uses the
      internal `llapi_scan_rec_dirent()` and `llapi_scan_rec_gather()`, not
      the public entry point, so the "stacked series shows the caller"
      argument does not cover the exported symbol. Either add an in-tree
      test that calls it, or expect the question on review.
- [ ] `Test-Parameters:` — neither commit has one. The default autotest run
      covers `sanity`; a line is only needed to ask for more.

## Open on the ticket

- [ ] The record's field set — proposed in the patch, from the prototype's
      168-byte record, minus what only a device scanner can know.
- [ ] Whether `libhsm_scanner.c` folds into this rather than remaining a second
      in-tree scanner.
- [ ] Components field is empty on the ticket; set it to llapi. Same on
      LU-20605, which wants utils.
- [ ] The filed description is Markdown and shows stray asterisks around bold
      lead-ins; replace it with the wiki-markup block below.

---

## Paste into Jira (wiki markup)

The filed description was written in Markdown; Jira renders wiki markup, so
{{**bold**}} came out as a literal asterisk around bold text. This is the same
description in Jira's syntax, for editing the ticket in place.

```
LFU starts client-side so the record contents and the consumer API are
settled before any kernel or wire-protocol work is committed to.

Most of the crawler is already in tree: LU-17814 landed
{{liblustreapi_pfind.c}} -- threaded traversal, attributes via
{{LL_IOC_MDC_GETINFO_V2}}, {{statx()}} fallback -- and
{{llapi_find_with_cb()}} / {{llapi_find_cb_t}} are exported.  This is not a
new crawler, but a callback that fills a per-object record instead of
printing.

New {{lustre/utils/liblustreapi_scan.c}}:

{code:c}
struct llapi_scan_rec;                  /* one object: FID, attrs, layout */
typedef int (*llapi_scan_cb_t)(const struct llapi_scan_rec *rec, void *data);

int llapi_scan_namespace(const char *path, struct llapi_scan_param *param,
                         llapi_scan_cb_t cb, void *data);
{code}

Exported by the existing {{llapi_*}} rule in {{liblustreapi.map}}; man page in
{{Documentation/man3/}}.  Named for what it does rather than for the
programme, since renaming an exported symbol later is an ABI event.

Its own ticket because the scanner has several queued consumers --
{{lfs find}} first, then the PCC-RO and Trash Can cleanup tools, FLR/EC
resync, HSM -- and each should be landable on its own.

h5. Scope
This defines an in-memory record and a callback contract, *not* a
serialization.  The Object Stream format is still open between FlatBuffers and
Cap'n Proto, so nothing here should freeze it.

h5. Review note
Pushed as one stacked Gerrit series with the {{lfs find}} conversion, so the
API's first caller is visible in the same push.
```
