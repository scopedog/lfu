# LU-20462: the epic — status comments

**LU-20462** is the LFU epic: Open, Artem Blagodarenko. Not ours to edit, so
anything we want recorded there goes in as a comment.

**Subtasks**, in the order they were filed:

| | | |
|---|---|---|
| LU-20603 | `llapi_scan_namespace()`, the record and the callback | 2.18 |
| LU-20605 | `lfs find` rebuilt on that record | 2.18 |
| LU-20606 | `llapi_scan_device()`, the ldiskfs device scanner | 2.18 |
| LU-20611 | find's predicates split from find's traversal; `lfind(8)` | 2.18 |
| LU-20720 | the in-kernel OSD scanner — the engine | 2.19 |
| LU-20721 | `lfs find` offloaded to the servers — **not written yet** | 2.19 |
| LU-20722 | `lfind` on a live target — the third `llapi_scan_device()` backend | 2.19 |
| *unfiled* | [`llapi_scan_mount()`](llapi-scan-mount.md) — client API and its transport | 2.19 |

The first four were the epic's own when we picked it up; **LU-20720, LU-20721
and LU-20722 we filed on 2026-09-09** and they are not reflected in the epic's
description, which is the owner's to change. The last row is drafted and not
filed; its commits carry the `LU-00000` placeholder.

Drafts for each are beside this file — [`osd-scanner.md`](osd-scanner.md),
[`lfs-find-on-osd-scanner.md`](lfs-find-on-osd-scanner.md),
[`lfind-on-osd-scanner.md`](lfind-on-osd-scanner.md),
[`llapi-scan-mount.md`](llapi-scan-mount.md).

Written for the rich-text editor, per the recipe that worked on LU-20611: no
double hyphens, asterisks or braces in the prose, and anything that must survive
literally inside a code fence.

---

## Comment: status, one correction, and TLU-219

**Posted 2026-08-19** by the ticket owner, trimmed before posting — the text
below is the draft that went in, not necessarily what LU-20462 now reads. Kept
as the record of what we asked to have said.

~~~
Status of the first step, replacing lfs find on the client side, and of the
server-side scanner that follows it. Seven changes are in review across the
four subtasks:

```
68094  LU-20603  llapi_scan_namespace(), the record and the callback
68095  LU-20605  lfs find rebuilt on that record
68156  LU-20606  llapi_scan_device(), the ldiskfs device scanner
68157  LU-20611  the cb_find_init() split it needs
68158  LU-20611  lfs find's predicate parser, moved where both can use it
68159  LU-20611  llapi_find_device()
68160  LU-20611  lfind(8)
```

All seven build on rocky8.10 and rocky9.6. Verified on a real MDT before
they were pushed: conf-sanity test_165 scans 108 objects and finds all 102
visible FIDs, zero misses, the six extras being the .lustre entries and the
three internal objects of LU-20602; sanity 56 is identical before and after
the parser move, 75 pass and 2 pre-existing failures either way; sanity 157c
passes. The device scan delivers the same object set at 1, 2, 4 and 8
threads.

h5. The description on this ticket is out of date
It says the Object Stream is FlatBuffers or MsgPack. MsgPack was ruled out
on 2026-08-18: the contenders are FlatBuffers and Cap'n Proto, and the
criterion given was zero copy access, LNet bulk RDMA integration and kernel
portability rather than encoded size or schema ergonomics. This ticket is
the page people read first, so it seems worth correcting.

h5. Parent FID and name are in the record now
Asked for in the last review round, so that a consumer can rebuild directory
trees in bulk rather than have pathnames shipped to it. The record carries
the parent FID, the name and the raw link xattr, which the device scanner
fills from trusted.link and the namespace scanner leaves clear. Whether
shipping full pathnames as well is cheaper than regenerating them is still
open, and still wants measuring rather than deciding.

h5. On TLU-219, which we have now read
Thank you for pointing at it. Two things we took from it. The FlatBuffers
recommendation rests on a message being built inside one pre-allocated
buffer that maps to a single LNet MD, and the same comment then withdraws
that argument for bulk transport, where an MD is backed by a lnet_kiov_t
page vector and Cap'n Proto segments map onto it directly. LFU is a bulk
workload by construction, so on that evidence the two candidates look
closer than the opening line reads. Second, c-capnproto is the first
concrete answer anyone has offered to kernel-side encoding, which we had
been carrying as a blocking unknown.

We also have three concerns about the kmap_local_page sketch in that
ticket, the LIFO unmapping rule, the page size cap on any single list or
blob, and the extra round trip carrying the segment table. They belong on
TLU-219 rather than here, and can wait until the format is settled.
~~~

---

## Comment: the 2.19 subtasks, filed (draft, not posted)

Written 2026-09-10. Records for the epic that the three 2.19 subtasks exist
and how they divide, since the epic's description still describes only the
2.18 work.

~~~
The server-side half now has tickets. Three subtasks were filed on
2026-09-09 and a fourth is drafted:

```
LU-20720  the in-kernel OSD scanner, the engine underneath the rest
LU-20722  lfind on a live target: llapi_scan_device()'s third backend,
          reading a mounted target through its own server
LU-XXXXX  llapi_scan_mount(): a client asks every MDT to scan itself and
          the records stream back in bulk, plus the transport that
          carries them
LU-20721  lfs find offloaded to the servers, which is the tool on top of
          that API and is not written yet
```

The split between the last two is the same one that separates LU-20722 from
LU-20721: an API deliverable is not a tool deliverable, and each is worth
reviewing on its own. LU-20722 and LU-20721 both consume the engine and are
independent of each other.

Two numbers from a two-node lab, an 88 thousand file filesystem, the
predicate mtime minus one and type f, five alternating pairs with caches
dropped on both nodes. Stock lfs find takes 8.770 seconds and 88028 round
trips to the MDT. The offloaded scan takes 0.292 seconds and 20. That is
thirty times on the wall clock and four thousand four hundred times on the
round trips, with a noise floor two orders of magnitude below the gap.

Our own lfs find, rebuilt on the scan record by LU-20605 and LU-20611, was
measured in the same run as a third arm: 9.037 seconds against upstream's
9.107, which is inside the run to run spread. The rewrite costs nothing on
the namespace walk.
~~~
