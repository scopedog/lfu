# LU-20462: the epic — status comments

**LU-20462** is the LFU epic: Open, Artem Blagodarenko, four subtasks (LU-20603,
LU-20605, LU-20606, LU-20611). Not ours to edit, so anything we want recorded
there goes in as a comment.

Written for the rich-text editor, per the recipe that worked on LU-20611: no
double hyphens, asterisks or braces in the prose, and anything that must survive
literally inside a code fence.

---

## Comment: status, one correction, one request

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

h5. A request
Could we see the TLU-219 analysis comparing FlatBuffers and MsgPack? It is
on the Whamcloud tracker and not readable from outside. Evaluating capnp-c
and flatcc for kernel portability, which is the open half of the format
question, is on the critical path for the in-kernel scanner, and starting
from that comparison would save repeating it.
~~~
