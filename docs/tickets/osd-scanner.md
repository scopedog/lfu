# LU-XXXXX — the in-kernel OSD scanner

**Status:** draft, not filed. Design: [`design-osd-port.md`](../design-osd-port.md),
scanner detail in [`design-osd-scanner.md`](../design-osd-scanner.md).
Covers groups A and B of the port; the userspace and find side is the sibling
ticket [`lfs-find-on-osd-scanner.md`](lfs-find-on-osd-scanner.md).

**Type:** New Feature · **Parent:** LU-20462 (the LFU epic) ·
**Fix version:** 2.19 · **Component:** none (the LU project defines none)

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim
and do not reflow it. Identifiers are in double braces because underscores
italicise outside them.

---

## Summary (plain text, not markup)

```
osd: scan a mounted target's object table and export an Object Stream
```

## Description (paste verbatim into Jira)

h3. What this is

A namespace scanner that runs inside the server, driving the OSD object table
iterator and exporting one record per object to userspace through a ring
buffer. It is the Input Scanner the Lustre Find Utility HLD calls Option 2, and
it is the piece the userspace scanners cannot replace.

h3. Why the userspace scanners are not enough

LU-20606 and LU-20613 read an MDT or OST as a block device or a ZFS dataset,
from outside the server. Both require the target to be *out of service*:

* ZFS refuses a live pool by design. {{libscan_zfs.c}} answers {{-EBUSY}} for a
pool in the {{ACTIVE}} state, and whether a quiesced imported pool can be read
safely at all is an open question on LU-20613.
* ldiskfs on a live device is exposed to torn reads. Under create heavy load a
prototype measured up to half of the allocated inodes reading back inconsistent,
with {{mode}} valid but {{nlink}} and {{dtime}} zero, which is on disk state
caught mid creation.

So a target that is serving clients cannot be scanned today. That is the gap
this closes, and it is a correctness gap rather than a performance one.

h3. What it does

The OSD already presents its object table as an ordinary DT index with a
standard {{dt_it_ops}} iterator, {{dt_otable_features}}, implemented by
ldiskfs, ZFS and WBCFS. LFSCK is its only current consumer. The iterator
returns a FID and nothing else.

This adds, at the OSD layer:

* attributes returned from the iterator, through the existing {{attr}} argument
of {{rec()}} whose documented purpose is to ask the iterator to return part of
the records. The directory iterator already uses it this way with the
{{LUDA_*}} flags, so there is precedent, no new vtable and no change to LFSCK,
which passes zero and keeps getting a bare FID.
* private iterator instances, so several enumerators walk disjoint ranges at
once. The default iterator is a per device singleton that answers {{-EALREADY}}
to a second {{init()}}, which is what makes a scan and an LFSCK run mutually
exclusive today.
* on ldiskfs, reading the inode table directly rather than through
{{ldiskfs_iget()}}, with an explicit readahead window.

and above it a module, {{lfu.ko}}, holding the enumerator threads, the ring and
the control device.

h3. Measured

All figures from a single box, both backends, control rows on the same build.

The unmodified iterator enumerates at 105k objects per second, against 705k for
the userspace device scanner on the same target. Private iterators take ldiskfs
to 2.03M and ZFS to 561k. Removing {{ldiskfs_iget()}} takes ldiskfs to 17.4M
warm at four threads and to 1,420,664 cold, at 99% of an NVMe stripe, against
the device scanner's 1,439,300 on the same stripe. That is a ratio of 0.99, and
0.78 hours against the HLD's four billion object hour.

The sequence is worth recording because the first answer was wrong about the
cause. A ceiling attributed twice to an architecture, first to the kernel path
and then to the iterator singleton, was each time attributable to a single
call.

Coexistence with LFSCK was measured rather than argued: a private iterator
returned the full namespace at 1.41M objects per second while a verifying OI
scrub was running, and the scrub finished with {{updated: 0, failed: 0}}, where
the default iterator gets {{-EALREADY}}.

h3. The Object Stream

The export follows {{lustre/ofd/ofd_access_log.c}}, which is the in tree
precedent for a kernel to userspace circular buffer, with three deliberate
differences:

* *A record is never dropped silently.* The access log increments a drop count
and returns {{-EAGAIN}} when full, which is right for a sampled diagnostic and
wrong for an enumeration, where a dropped record makes an incomplete listing
look complete. The producer stalls instead, and where dropping is unavoidable
the stream carries an explicit gap marker.
* *One buffer, many consumers.* The access log gives every reader its own ring.
The point of this scanner is that one scan's IO serves every consumer, so
readers share a buffer and hold their own cursors into it.
* The record is a compact fixed layout of 168 bytes, versioned, with the
consumer refusing a version or size mismatch rather than misparsing it. At the
measured rate that is 239 MB/s of ring traffic.

h3. Filtering in kernel

Predicates are evaluated before a record enters the ring, so a scan for a rare
property does not copy every object to userspace to reject it there. Over four
billion objects the difference is roughly 672 GB copied against a few hundred
kilobytes.

The evaluator is one source file compiled into both the kernel module and the
userspace scanners, so the two give the same answer by construction rather than
by testing. The filter program is validated on arrival, with magic, version,
size and index range all checked before anything is evaluated.

The first version evaluates predicates answerable from the attributes the
iterator already has. Predicates needing an xattr follow, and need the
iterator extension that returns them.

h3. Scope

In scope:

* the OSD iterator extensions above, for ldiskfs and ZFS
* {{lfu.ko}}: enumerator threads, ring, control device, in kernel filtering
* tests, including a differential test against the userspace device scanner on
a quiescent target, which is a stronger oracle than either scanner has alone

Not in scope, and each has its own ticket or needs one:

* reaching this from {{lfs find}}'s vocabulary, which is the sibling ticket
* exporting scan requests to servers over the wire from a client, which the HLD
describes as the Client Bulk RPC Filter Rule Module
* WBCFS, pending a decision on whether it is wanted

h3. Relationship to LU-20591

LU-20591 builds a scanner on the same {{osd_otable_it}} primitive. Its walk
calls {{dt_locate()}} and {{dt_attr_get()}} per object, which is the path this
work removes, so the OSD layer changes here make that series faster too.

The intent is to land the OSD layer changes independently of whichever control
interface is preferred, so that the fast path is shared rather than duplicated,
and to take {{DOIF_NOSCRUB}} from LU-20591 rather than re derive it.

h3. Known risks

* *Foreground impact is unmeasured.* A scan now runs inside the server and
consumes its CPU and caches. No throughput figure speaks to what that costs a
serving MDS, and nothing should ship on throughput alone.
* *Reading the inode table directly is fresher than disk but is not the live
inode.* Blocks are updated when the inode is marked dirty rather than at
writeback, so the mid creation window is much narrower than for the device
scanner, but it is not provably closed and has not been measured under create
heavy load.
* *The raw parse does not verify the inode metadata checksum,* so it reports a
corrupt inode where {{ldiskfs_iget()}} would refuse it. That is defensible for
a scanner whose consumer re-reads before acting, but it belongs in the
documented contract rather than in a code comment.
* *Whether extending {{rec()}}'s {{attr}} argument is acceptable upstream,* or
whether a separate index feature is preferred, is the one open question that
could force a redesign rather than a revision.

---

## Notes for us, not for Jira

**The first move is not code.** Two things want settling before A1 is written:

1. **Cost to existing users** — can attribute capture happen inside
   `osd_iit_iget()` without slowing OI Scrub and LFSCK, which share the path?
   Answerable by reading code today, and it shapes the patch.
2. **The group-A split** — put to Andreas and Jinshan as a question, not a
   patch: can the iterator extensions land independently of the control
   interface?

**Change breakdown** (from `design-osd-port.md` §5): A1 `rec()` attributes,
A2 private iterators, A3 block parsing, A4 readahead, A5 xattrs from the
iterator; then B1 the module and ring, B2 tier-0 filtering, B3 tier-1.
