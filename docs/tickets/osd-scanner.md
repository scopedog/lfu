# LU-XXXXX — the in-kernel OSD scanner

**Status:** draft, not filed. Design: [`design-osd-port.md`](../design-osd-port.md),
scanner detail in [`design-osd-scanner.md`](../design-osd-scanner.md).
Covers groups A and B of the port; the userspace and find side is the sibling
ticket [`lfs-find-on-osd-scanner.md`](lfs-find-on-osd-scanner.md).

**Type:** Technical task · **Parent:** LU-20462 (the LFU epic) ·
**Fix version:** 2.19 · **Component:** none (the LU project defines none)

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim
and do not reflow it. Identifiers are in double braces because underscores
italicise outside them.

---

## Summary (plain text, not markup)

```
LFU: in-kernel OSD scanner
```

## Description (paste verbatim into Jira)

h3. What this is

A namespace scanner that runs inside the server, driving the OSD object table
iterator and exporting one record per object to userspace through a ring
buffer. It is the Input Scanner the LFU HLD calls Option 2.

h3. Why it is needed

The userspace device scanners of LU-20606 and LU-20613 both require the target
to be out of service. ZFS refuses a live pool by design, answering {{-EBUSY}}
for a pool in the {{ACTIVE}} state. ldiskfs on a live device is exposed to torn
reads: under create heavy load a prototype measured up to half of the allocated
inodes reading back inconsistent, caught mid creation.

So a target that is serving clients cannot be scanned at all today. This is a
correctness gap, not a performance one.

h3. What it adds

The OSD already presents its object table as a DT index with a standard
{{dt_it_ops}} iterator, {{dt_otable_features}}, implemented by ldiskfs, ZFS and
WBCFS. It returns a FID and nothing else, and LFSCK is its only consumer.

At the OSD layer:

* attributes returned from the iterator, through the existing {{attr}} argument
of {{rec()}}. The directory iterator already selects record content this way
with the {{LUDA_*}} flags, so this needs no new vtable and does not change
LFSCK, which passes zero and keeps getting a bare FID.
* private iterator instances, so several enumerators walk disjoint ranges at
once. The default iterator is a per device singleton answering {{-EALREADY}} to
a second {{init()}}.
* on ldiskfs, reading the inode table directly instead of through
{{ldiskfs_iget()}}, with a readahead window.

Above it, {{lfu.ko}}: enumerator threads, the ring, the control device, and
filtering.

h3. Measured

The unmodified iterator enumerates at 105k objects per second against 705k for
the userspace device scanner. Private iterators take ldiskfs to 2.03M and ZFS
to 561k. Removing {{ldiskfs_iget()}} takes ldiskfs to 1,420,664 cold at 99% of
an NVMe stripe, against the device scanner's 1,439,300 on the same stripe, a
ratio of 0.99, and 0.78 hours against the HLD's four billion object hour.

LFSCK coexistence was measured rather than argued: a private iterator returned
the full namespace at 1.41M objects per second while a verifying OI scrub ran,
and the scrub finished with {{updated: 0, failed: 0}}.

h3. The Object Stream

Modelled on {{lustre/ofd/ofd_access_log.c}}, the in tree precedent for a kernel
to userspace circular buffer, with three differences. A record is never dropped
silently, because a dropped record makes an incomplete listing look complete:
the producer stalls, and an unavoidable drop sets an explicit gap marker.
Consumers share one buffer and hold their own cursors, since one scan's IO is
meant to serve all of them. The record is a compact 168 byte fixed layout,
versioned, and a version or size mismatch is refused rather than misparsed.

h3. Filtering in kernel

Predicates are evaluated before a record enters the ring, so a search for a
rare property does not copy every object to userspace to reject it there. Over
four billion objects that is roughly 672 GB copied against a few hundred
kilobytes.

The evaluator is one source file compiled into both the kernel module and the
userspace scanners, so the two agree by construction. The filter program is
validated on arrival before anything is evaluated. The first version handles
predicates answerable from the attributes the iterator already has; those
needing an xattr follow.

h3. Scope

In scope: the OSD iterator extensions for ldiskfs and ZFS, {{lfu.ko}}, and
tests including a differential run against the userspace device scanner on a
quiescent target, which is a stronger oracle than either scanner has alone.

Not in scope: reaching this from {{lfs find}}, which is the sibling ticket;
exporting scan requests from a client over the wire, which is the HLD's Client
Bulk RPC Filter Rule Module; and WBCFS, pending a decision.

h3. Relationship to LU-20591

LU-20591 builds a scanner on the same {{osd_otable_it}} primitive, with a walk
that calls {{dt_locate()}} and {{dt_attr_get()}} per object. The OSD layer
changes here remove that path, so they make that series faster too. The intent
is to land them independently of whichever control interface is preferred, and
to take {{DOIF_NOSCRUB}} from LU-20591 rather than re derive it.

h3. Known risks

* Foreground impact is unmeasured. A scan now consumes the server's CPU and
caches, and no throughput figure speaks to what that costs a serving MDS.
* Reading the inode table directly is fresher than disk but is not the live
inode, so the mid creation window is narrower than the device scanner's but not
provably closed.
* The raw parse does not verify the inode metadata checksum, so it reports a
corrupt inode where {{ldiskfs_iget()}} would refuse it. Defensible, but it
belongs in the documented contract.
* Whether extending {{rec()}}'s {{attr}} argument is acceptable upstream is the
one question that could force a redesign rather than a revision.

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
