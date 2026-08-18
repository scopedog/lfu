# Draft ticket: client-side namespace scanner API in liblustreapi

**Status:** draft, not filed. The reusable half of LU-20462's first step
(2026-08-18 meeting: *replacing `lfs find` on the client side*). Its first
consumer is drafted separately in
[`lfs-find-on-llapi-scan.md`](lfs-find-on-llapi-scan.md).

**File** linked to **LU-20462**, not as a sub-task — LU-20462's related work
(LU-20591, LU-13650) is tracked as linked issues. Type New Feature · Components
llapi · Related LU-20462, LU-17814.

---

## Summary

llapi: namespace scanner API emitting per-object records to a consumer callback

## Description

LFU's rollout starts client-side deliberately: a namespace Input Scanner gives a
working end-to-end pipeline on unmodified clients and servers, which shakes out
the record contents and the consumer API before any kernel or wire-protocol work
is committed to.

**Most of the crawler is already in tree.** LU-17814 landed
`lustre/utils/liblustreapi_pfind.c`: a threaded work-queue traversal, attribute
fetch through `LL_IOC_MDC_GETINFO_V2`, a `statx()` fallback for non-Lustre
paths, and `lfs find --threads N` on top. `llapi_find_with_cb()` and
`llapi_find_cb_t` are already exported in `include/lustre/lustreapi.h`. So this
is not a new crawler — it is a callback that fills a per-object record instead
of printing, driven by the thread pool that already exists.

**Why its own ticket.** The scanner is a component with several queued
consumers, not a detail of any one of them: `lfs find` first, then the PCC-RO
cache-eviction and Trash Can purge tools (which want to be written as LFU
consumers before 2.18 closes that window), then FLR/EC resync, HSM and tiered
storage. A ticket per consumer, all depending on this one, keeps each landable
on its own.

### Proposed shape

New `lustre/utils/liblustreapi_scan.c`:

```c
struct llapi_scan_rec;                  /* one object: FID, attrs, layout */
typedef int (*llapi_scan_cb_t)(const struct llapi_scan_rec *rec, void *data);

int llapi_scan_namespace(const char *path, struct llapi_scan_param *param,
			 llapi_scan_cb_t cb, void *data);
```

Implemented over `llapi_find_with_cb()`. Exported automatically by the `llapi_*`
rule in `liblustreapi.map`. Man page in `Documentation/man3/`.

**Named for what it does, not for the project.** "LFU" is the programme, not the
function; a reusable client-side scanner should still read sensibly to someone
who has never heard of it, and renaming an exported symbol later is an ABI
event.

### What this must not do

**It must not freeze the binary Object Stream format.** FlatBuffers versus
Cap'n Proto is open and on the critical path — the criterion is zero-copy access
plus LNet bulk RDMA integration plus kernel portability, with prior analysis on
TLU-219. This ticket therefore defines an **in-memory record and a callback
contract**, not a serialization. Bytes on a wire come once the format is
settled. That scoping is deliberate and should be stated in the ticket, not left
for a reviewer to ask about.

### Review note

An exported API with no in-tree caller normally draws objection. Push this and
the `lfs find` conversion as **one stacked Gerrit series** so the caller is
visible in the same push, while the tickets stay separate.

---

## Before filing

- [ ] Confirm the API name and the record's field set.
- [ ] Check whether `libhsm_scanner.c` should fold into this rather than remain
      a second in-tree scanner.
