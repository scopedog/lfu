# LU-XXXXX — find's predicates over the in-kernel OSD scanner

**Status:** draft, not filed. Design: [`design-osd-port.md`](../design-osd-port.md)
§2 and §4. Covers group C, levels L1 and L2; the scanner itself is the sibling
ticket [`osd-scanner.md`](osd-scanner.md).

**Type:** Technical task · **Parent:** LU-20462 (the LFU epic) ·
**Fix version:** 2.19 · **Depends on:** the OSD scanner ticket ·
**Component:** none

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim
and do not reflow it.

**Scope note for us:** this is drafted for the *server local* levels — `lfind`
and `lfs find` reaching a live target on the node that serves it. The client
side offload, where `lfs find` exports search requests to every MDT over the
wire, is deliberately a separate ticket and is roughly the size of everything
done so far. See the response accompanying this draft; if the intent was the
client side, this draft needs replacing rather than extending.

---

## Summary (plain text, not markup)

```
LFU: run 'lfs find' predicates over the in-kernel OSD scanner
```

## Description (paste verbatim into Jira)

h3. What this is

Reaching the in-kernel OSD scanner from the vocabulary {{lfs find}} already
has, so a target that is serving clients can be searched with the same
predicates, by the same tools, as one that is stopped.

h3. What already exists

LU-20611 separated find's predicates from find's traversal, so
{{llapi_find_device()}} runs them over objects from {{llapi_scan_device()}}
rather than a namespace walk, with {{lfind(8)}} on top.
{{llapi_scan_device()}} in turn selects a backend at run time. Two exist,
ldiskfs and ZFS, both reading a target that is out of service, and both loaded
as plugins behind one five entry point interface.

The prototype consumer of the kernel scanner implements that same interface, so
this is mostly connecting two halves that already match.

h3. What changes

A third backend, selected when the named target is in service, reading the
Object Stream from the kernel module instead of the device. It compiles the
predicates into the filter the kernel evaluates and hands them over before the
first record, so what arrives is already the answer and nothing is re-evaluated
in userspace. It checks the stream's version and record size before trusting a
record. It reports which attributes the module can serve, so a filter the
kernel cannot answer is refused rather than silently matching nothing. Thread
count is not a knob: parallelism stays behind the enumerator in the kernel.

h3. What does not change

Nothing above {{llapi_scan_device()}}. The predicate set,
{{llapi_find_device()}}, {{lfind(8)}}, the pathname options, the record and the
manual pages are untouched. The same command that searches a stopped target
searches a running one.

h3. Scope

In scope: the backend and its selection rule; the diagnostic for a target that
is in service when the module is not loaded, which must say so rather than
reporting that no backend exists; {{lfind}} on a mounted target and its manual
page; and tests, including a differential run against the device backend on a
quiescent target.

Not in scope: the client side, where {{lfs find}} exports search requests to
every MDT in parallel and merges the results. That is the HLD's Client Bulk RPC
Filter Rule Module, it needs an RPC, a connect flag and a cross target merge,
and one question is unanswered ahead of it: how duplicate FIDs across merged
streams are handled while a file is migrating. It wants its own ticket.

h3. Risk

Not a crash, but a silent difference in which objects match between a target
scanned as a device and the same target scanned through the kernel. The
differential test is the control for exactly that, and it is cheap because both
paths are in the tree.

---

## Notes for us, not for Jira

**The seam is the whole argument.** `src/lfu_scan_kmdt.c` and the shipped
`struct llapi_scan_backend` have the same five entry points, arrived at
independently. Worth not overstating it in the ticket — it reads as luck rather
than design — but it is why this ticket is small.

**Where the care goes:** `scan_backend_kind()`. After round 23 an absolute path
routes to ldiskfs and everything else reads as a ZFS dataset name. A live target
has to be recognised before either, and "the module is not loaded" must not
surface as "no backend for this build", which is the message that already exists
for a different cause.

**Change breakdown** (`design-osd-port.md` §5): C1 the backend, C2 the routing
and diagnostics, C3 `lfind` on a mounted target plus the man page.
