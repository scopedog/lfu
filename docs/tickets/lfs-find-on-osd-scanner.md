# LU-XXXXX — `lfs find` offloaded to the servers

**Status:** draft, not filed. Design: [`design-osd-port.md`](../design-osd-port.md)
§4 (level L3). The scanner itself is the sibling ticket
[`osd-scanner.md`](osd-scanner.md).

**Type:** Technical task · **Parent:** LU-20462 (the LFU epic) ·
**Fix version:** 2.19 · **Depends on:** the OSD scanner ticket ·
**Component:** none

**Scope, settled 2026-09-09:** `lfs find` runs on a client and `lfind` runs on
a server, so *"`lfs find` on the OSD scanner"* can only mean the client sending
the search to the servers. That is this ticket. Reaching the scanner from a
process on the server node — `lfind` against a live target — is a separate and
much smaller ticket, not written yet.

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim
and do not reflow it.

---

## Summary (plain text, not markup)

```
LFU: 'lfs find' offloaded to the servers over bulk RPC
```

## Description (paste verbatim into Jira)

h3. What this is

{{lfs find}} on a client, sending the search to every MDT instead of walking
the namespace. The servers scan with the in-kernel OSD scanner and filter
there; the surviving records stream back to the client, which merges them,
applies whatever the server could not, and prints. These are the HLD's Server
and Client Bulk RPC Filter Rule Modules.

h3. Why

A namespace walk costs at least one RPC per object and floods the client
dcache. A server side scan reads the object table sequentially, at 1.42M
objects per second per target measured cold, and returns only what matched.
The HLD puts it plainly: it should be possible for {{lfs find}} to export
search requests directly to multiple servers in parallel rather than scanning
the namespace locally, and server offload of namespace scanning has already
been used to improve IO500 find performance.

h3. What it adds

*Server side.* Export the Object Stream from the MDS or OSS to a client,
similar to Changelog access, with server side authentication and result
filtering so the stream carries only objects the requesting user may see.

*Client side.* Receive the stream by bulk RDMA into the same Object Stream
kernel API the OSD produces it with, so access is uniform at both ends rather
than two formats and two parsers.

*Negotiation.* A new {{OBD_CONNECT2_FIND_UTILITY}} connect flag says whether
the pair supports this at all. Per scan, the Scan Request then negotiates which
scanners and filters the server has, so the client can tell whether the search
runs entirely on the server, partly on the server with the rest filtered on the
client, or not at all. The middle case is not optional: it is how a predicate
the server cannot evaluate still gets answered.

*{{lfs find}} itself.* Issue the scan to every MDT in parallel, merge the
streams, apply the residue predicates locally, and print. Predicates needing a
pathname become answerable again here, unlike on a server side scan, because a
client can resolve a FID to a name.

h3. Phasing

The HLD sets it out: usable first by administrators from a client rather than
from the server, and by regular users later. An administrator only first
version defers the hardest part, filtering results by POSIX permissions, ACLs,
filesets and nodemaps, without deferring the transport or the negotiation.

h3. Scope

In scope: the server side export and its access control; the client side
receiver; the connect flag and the per scan negotiation; {{lfs find}} issuing,
merging and applying residue; and tests, including the same search run as a
namespace walk and as an offloaded scan, which must agree.

Not in scope: the scanner itself, which is the sibling ticket, and reaching
that scanner from a process on the server node, which is a separate ticket.

h3. Open questions

* *Duplicate FIDs across merged streams.* A file being migrated can appear on
more than one MDT. No revision of the HLD addresses how the client resolves
that, and it has to be settled before the merge is written.
* *The record format.* The HLD asks for an extensible binary format that can
add features as needed rather than monolithic data structures. The scanner's
wire record is a fixed layout, which is fast and simple locally but is the
opposite of what that asks for. The choice between candidate formats was
deferred in August; this is what makes it urgent.
* *Which predicates are residue,* and whether the split is fixed or negotiated
per scan.

h3. Risk

The risk here is not a wrong answer, it is a disclosure. A scan that returns
objects the requesting user cannot see is a security bug, and the filtering
that prevents it runs on the server against attributes the client never sees.
That is why the administrator only phase is worth having: it separates
transport correctness from access control correctness and lets each be tested
on its own.

---

## Notes for us, not for Jira

**The transport, from the HLD.** The client uses the same Object Stream kernel
API as the OSD, fed by bulk RDMA. No opcode is named, so the mechanism
underneath is open — `tgt_obd_idx_read()` is worth a look, since it already
carries a resume cursor, an attribute mask and a bulk PUT, and its
`dt_index_read()` path drives the same `dt_it_ops` the scanner extends.

**Negotiation is per-scan as well as per-connection**, and the "partially on the
server" case is called out explicitly. That makes the residue mechanism a
requirement rather than a refinement, which is more than we had assumed.

**The wire format question is now on the critical path.** Deferred on 2026-08-19
as not-ours and never evaluated. A fixed 168-byte struct is at odds with the
HLD's "extensible binary data format", and the disagreement only bites once the
record crosses a version boundary — which is exactly what this ticket does.
Someone needs to own that evaluation before the record is committed to.

**Where the care goes:** access control. Everything else here is plumbing that
either works or does not. Result filtering by ACL, fileset and nodemap is the
part where being wrong is a disclosure, and it is why the administrator-only
phase earns its place.
