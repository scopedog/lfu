# Draft ticket: client-side namespace scanner API in liblustreapi

**Status:** draft, not filed. The reusable half of LU-20462's first step
(*replacing `lfs find` on the client side*); its first consumer is drafted in
[`lfs-find-on-llapi-scan.md`](lfs-find-on-llapi-scan.md).

**File** linked to **LU-20462**, not as a sub-task — LU-20591 and LU-13650 hang
off it the same way. Type New Feature · Components llapi · Related LU-20462,
LU-17814.

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
conversion, so the API's first caller is visible in the same push.

---

## Before filing

- [ ] Confirm the API name and the record's field set.
- [ ] Check whether `libhsm_scanner.c` folds into this rather than remaining a
      second in-tree scanner.
