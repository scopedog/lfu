# LU-XXXXX — `llapi_scan_mount()`, a scan from a client

**Status:** draft, 2026-09-10, **not yet filed**. Commits carry the
placeholder `LU-00000` until a number exists. Design:
[`design-llapi-scan.md`](../design-llapi-scan.md),
[`design-osd-port.md`](../design-osd-port.md) §4.

**Type:** Technical task · **Parent:** LU-20462 (the LFU epic) ·
**Depends on:** LU-20720 · **Blocks:** LU-20721 · **Component:** none ·
**Targets 2.19** (no Jira version exists for it; no LU-20462 subtask sets
fixVersion)

**Split out of LU-20721 on 2026-09-10**, which was scoped as "`lfs find`
offloaded to the servers" and had grown a public API that has nothing to do
with `lfs find`. Same split, and same reason, as LU-20722: an API deliverable
is not a tool deliverable. LU-20721 keeps its title and now depends on this.

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim
and do not reflow it.

---

## Summary (plain text, not markup)

```
LFU: llapi_scan_mount() to scan a filesystem's MDTs from a client
```

## Description (paste verbatim into Jira)

h3. What this is

A client asks every MDT of a mounted filesystem to scan its own objects, and
the records stream back in bulk. One library call, {{llapi_scan_mount()}}, and
no round trip per object.

h3. What already exists

LU-20720 put the OSD object-table scanner in the kernel and exports its Object
Stream through a character device; LU-20722 consumes that locally as a
{{llapi_scan_device()}} backend. Both run on the server that holds the target.
Nothing lets a client reach the stream.

The transport largely existed too. {{dt_index_walk()}} drives an index through
{{init/load/next/key/key_size/rec/store}} and the otable iterator implements
every one, having been built as a {{dt_index}} for LFSCK; the container format
already carries variable-size records under {{II_FL_VARREC}} and no keys under
{{II_FL_NOKEY}}; and {{rp_attrs}} carries iterator flags from the request to
{{init()}}.

h3. What this adds

* {{dt_otable_lfu_rec()}} in obdclass builds the wire record from
{{rec(DORA_ATTR)}} and {{rec(DORA_XATTR)}}, so the ring and an RPC carry the
same bytes from one builder.
* {{rec_size()}} and {{rec(DORA_LFU)}} on the ldiskfs and ZFS otable
iterators, and {{dt_otable_features}}, which was declared with no initialiser.
* The otable FID past {{dt_index_read()}}'s whitelist; no dt lock or version
on an object that is an iterator rather than a file.
* {{DOIF_INDEX}}: a second {{load()}} mode that positions *at* the hash and
answers as an index does. {{load()}}'s existing return cannot change, because
LFSCK reads a positive value as "the table is over".
* {{LL_IOC_LFU_SCAN}}: llite to the MD export, lmv to the MDT named in it, mdc
sending {{OBD_IDX_READ}} with a bulk of the caller's pages, as
{{osp_it_fetch()}} reads an index across MDTs.
* {{llapi_scan_mount()}} and {{libscan_client.c}}: a scan backend whose unit
of work is an MDT rather than a slice of a target, so the existing worker
sharding scans N MDTs in parallel. {{llapi_scan_obj}} gains
{{so_mdt_index}}, since one target now covers many MDTs and only the record
knows which answered.
* {{llapi_scan_mount.3}}.

h3. Measured

Two nodes, an 88k-file filesystem, {{-mtime -1 -type f}}, five alternating
pairs with caches dropped on both:

{noformat}
arm                 count   median wall   RPCs to MDT0000
stock lfs find      87944       8.770 s             88028
offloaded stream    87958       0.292 s                20
{noformat}

30x on the median and 4401x fewer round trips. The same fixture on one node
gave 5.394 s for the walk, so a loopback client understates it: the round
trips it does not pay are the point.

h3. Correctness

{{llapi_scan_mount()}} against a scan of the targets themselves: 87961 =
87961 visible and 88051 = 88051 with internal objects, diff 0 both, and the
same from a client that is not the server. 87957 of those records carry a
name and parent FID rebuilt from {{trusted.link}}.

Resumes are where an index walk goes wrong, and one RPC exercises none of
them, so the client buffer was shrunk to force boundaries: ldiskfs 2446 calls
with 2445 resumes, ZFS 1 through 58 calls, diff 0 at every size.

h3. What this is not

It scans the whole filesystem whatever directory names it: a target has no
notion of a subtree. So it is a filesystem sweep, not a way to look through
one directory, and the manual page says so. Choosing between it and
{{llapi_scan_namespace()}} is not part of this and is not yet designed.

Consumers need {{CAP_SYS_ADMIN}}. Server-side filtering by user is what the
HLD defers, and so does this.

h3. Note on scope

{{DORA_LFU}} and {{DOIF_INDEX}} are iterator capabilities and are left in
LU-20720 rather than moved here, since anything driving the otable could use
them. They are listed above because this is what they were built for.
