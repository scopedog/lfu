# LU-XXXXX — find's predicates over the in-kernel OSD scanner

**Status:** draft, not filed. Design: [`design-osd-port.md`](../design-osd-port.md)
§2 and §4. Covers group C, levels L1 and L2; the scanner itself is the sibling
ticket [`osd-scanner.md`](osd-scanner.md).

**Type:** New Feature · **Parent:** LU-20462 (the LFU epic) ·
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
llapi: run lfs find's predicates over a scan of a mounted target
```

## Description (paste verbatim into Jira)

h3. What this is

Reaching the in-kernel OSD scanner from the vocabulary {{lfs find}} already
has, so that a target which is *serving clients* can be searched with the same
predicates, by the same tools, as one that is stopped.

h3. What already exists

LU-20611 separated find's predicates from find's traversal. The deciding half
of {{cb_find_init()}} moved behind {{struct find_ctx}}, and
{{llapi_find_device()}} became a second consumer of it: the same predicates,
with objects arriving from {{llapi_scan_device()}} instead of a namespace walk.
{{lfind(8)}} is the utility on top.

Underneath that, {{llapi_scan_device()}} selects a backend at run time. Two
exist, ldiskfs and ZFS, each reading a target that is out of service. They are
loaded as plugins and share one interface, five entry points named
{{sb_open}}, {{sb_close}}, {{sb_worker_init}}, {{sb_worker_fini}} and
{{sb_scan_chunk}}.

The prototype consumer of the kernel scanner, written separately, implements
the same five. So the work here is mostly connecting two interfaces that
already match, rather than designing one.

h3. What changes

A third backend, selected when the named target is in service, reading the
Object Stream from the kernel module rather than the device.

* It compiles the predicates into the filter program the kernel evaluates, from
the same vocabulary as everywhere else, and hands it over before the first
record. What arrives is therefore already the answer, and the library neither
pre filters nor re-evaluates what it receives.
* It checks the stream's version and record size before trusting a single
record, and refuses a mismatch rather than misparsing it.
* It reports which attributes and which predicates the module's backend can
actually serve, so a filter the kernel cannot answer is refused with the same
message the device backends give, rather than silently matching nothing.
* Parallelism stays behind the enumerator in the kernel. The stream is ordered
and has one reader; the thread count is not a knob here.

h3. What does not change

Nothing above {{llapi_scan_device()}}. The predicate set, {{llapi_find_device()}},
{{lfind(8)}}, the pathname options, the record and the manual pages are all
untouched. A user learns no new concept: the same command that searches a
stopped target searches a running one.

h3. Why it is worth doing separately

The scanner is only reachable by a purpose built consumer until this exists.
This is what turns it into something an administrator can use, and it is also
what makes the scanner testable against a real oracle: with both a device
backend and a kernel backend behind one interface, the same target can be
scanned both ways and the answers compared object by object. Neither has that
oracle alone.

h3. Scope

In scope:

* the third backend and its selection rule
* the diagnostics: a target that is in service when the module is not loaded
should say so, rather than reporting that no backend exists
* {{lfind}} on a mounted target, and the manual page
* tests: differential against the device backend on a quiescent target, the
same predicate pushed down against applied in userspace, and the object set
against {{lfs find}} on the mounted filesystem

Not in scope:

* the client side, where {{lfs find}} exports search requests to every MDT in
parallel and merges the results. That is the HLD's Client Bulk RPC Filter Rule
Module, it needs an RPC, a connect flag and a cross target merge, and it has an
unanswered question ahead of it: how duplicate FIDs across merged streams are
handled when a file is being migrated. It wants its own ticket.

h3. Risk

The risk is not a crash. It is a silent difference in which objects match,
between a target scanned as a device and the same target scanned through the
kernel. The differential test above is the control for exactly that, and it is
cheap to run because both paths are already in the tree.

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
