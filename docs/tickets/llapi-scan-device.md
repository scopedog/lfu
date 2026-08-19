# LU-XXXXX: device scanner behind `llapi_scan_device()`

**Not yet filed.** Technical task, parent **LU-20462**, related to **LU-20603**
(the scanner API, [`llapi-scan-api.md`](llapi-scan-api.md)) and **LU-20602**
(internal objects LMA cannot identify). Step 3 of
[`architecture.md`](../architecture.md) §12 — the first real performance win,
and the first piece that runs on a server.

Design of record: [`design-llapi-scan-device.md`](../design-llapi-scan-device.md).
Mechanism and measurements: [`design-ldiskfs-scanner.md`](../design-ldiskfs-scanner.md).

Two changes, to be pushed as one stacked series the way LU-20603/LU-20605 were:
the API and its plugin, then `lfs find --device` as the consumer. **Components:
llapi** for the first, **utils** for the second — set them at filing time; both
of the last two tickets went in with Components empty.

---

## Summary

llapi: scan an ldiskfs target directly, behind the scanner API

## Description

`llapi_scan_device()` produces the same per-object records as
`llapi_scan_namespace()` (LU-20603), reading an MDT or OST **directly from the
block device** with libext2fs instead of walking a mounted namespace from a
client.

It needs no kernel change, no server modification and no mount, so it runs
against existing servers and against a snapshot or a passive failover partner.
It follows e2scan and Lester, the Lustre Lister. The device is opened
**read-only** and there is no write path: LFU reads, LFSCK and OI Scrub repair.

**Why it is worth a second producer.** A client-side namespace walk costs an
RPC round trip per object. Reading the inode table costs a sequential device
read. Measured on a 20M-object MDT on NVMe, a cold full scan ran at 1.44M
objects/s, 94% of the device's bandwidth, flat in thread count because the
device saturates before the scanner does. On a 1024-byte MDT inode every Lustre
xattr is inline, so the FID, layout, SOM size and linkea come back with the
inode: the measured external-EA-block rate on a real MDT was 0.0%.

**One record, two producers.** `struct llapi_scan_rec` is versioned by
`sr_size` and carries a validity mask, so a field a producer cannot answer for
is distinguishable from one that is genuinely zero. A device scan fills a
different subset of the same record, and the consumers queued behind LFU
should not have to care which producer filled it. The record grows `sr_projid`,
`sr_parent_fid`, the raw linkea, the object id, the LMA flags and an object
class; fields are only ever appended. `LLAPI_SCAN_LAZY_SIZE` needs nothing new
— `trusted.som` is exactly what that bit already means.

**libext2fs stays out of liblustreapi.** The ldiskfs half builds as
`scan_ldiskfs.so` and is `dlopen`ed on first use, the way `mount.lustre` loads
`mount_osd_ldiskfs.so`; a client build has no plugin and the call returns
-ENOTSUP. Only a `--disable-plugins` server build links libext2fs into the
library, and that build already links it into `mount.lustre`.

**What a device scan does not have.** Paths. It recovers names and parent FIDs
from the linkea; resolving those into a path is an Output Format concern and is
priced separately. The record says so through its validity mask rather than
returning an empty string.

**What it sees that a namespace walk does not.** Internal objects, OST data
objects, HSM agent inodes and orphans. Each record carries its class, and the
default is to emit only namespace-visible objects, so a consumer that deletes
things does not have to know the OI file layout to avoid eating one. Three
internal objects still classify as visible because LMA alone cannot identify
them — LU-20602 is the durable fix; until it lands the man page says so.

**Consistency.** The scan does not lock and does not coordinate with the MDS.
It sees a stale, un-replayed view, which is the right trade for a scan of this
kind, and it detects and skips objects caught mid-update rather than emitting
them wrong: measured at 0.05% of allocated inodes under sustained creates and
zero on a quiescent target. The count comes back to the caller, because an API
that drops objects silently is not one a space-accounting consumer can build on.

**Acceptance:** against a mounted, serving MDT, the scanner's FID set contains
every FID `lfs find` reports from a client — **zero misses**, the property that
matters for a scanner a cleanup tool will act on. Extras are expected and
bounded: the `.lustre` pseudo-directories and the three objects of LU-20602.

**Scope:** the ldiskfs backend and the call that reaches it. Checkpoint and
restart, rate limiting, the ZFS backend behind the same call, and the Object
Stream serialization are each separate. The record stays in-memory: the wire
format LU-20462 will send is still being chosen, and nothing here should
freeze it.

---

## Second change (`lfs find --device`)

### Summary

lfs: find over a device scan

### Description

`lfs find` gains a device mode: given `--device`, it filters records from
`llapi_scan_device()` instead of walking a mounted namespace. The predicate
vocabulary is the one `lfs.c` already parses, which is the point — LFU replaces
`lfs find` rather than growing a second command with a second copy of the same
predicate table.

Three differences the mode has to make explicit, each a place behaviour is not
preserved:

- Output is the FID, because a device scan has no paths. A `-printf` format
  asking for one is refused at parse time rather than printing blank.
- A predicate the target cannot answer is refused before the scan starts, not
  answered "no matches" — the two are indistinguishable to a user.
- Root only, MDT-only, and no access control whatsoever. `--size` on a striped
  file is `trusted.som`'s answer or none, which is `--lazy` semantics by
  construction.

**Acceptance:** the `sanity.sh` 56\* series stays green — the device mode adds
a path, it does not change the existing one — plus a new ldiskfs-only test that
runs the scan against the mounted MDT and diffs its FID set against `lfs find`.

---

## Checklist

- [x] `sr_projid`, the `LLAPI_SCAN_ALL_MASK` fix and a `sp_size` rule that
      lets the parameter struct grow, folded into LU-20603 while it is still
      in review (all three additive; they carry the re-wrapped commit
      messages that were held back)
- [x] `libscan_ldiskfs.c` — prototype ported to upstream style
- [x] `liblustreapi_scan_device.c` — ops table, dlopen, -ENOTSUP path
- [x] `Makefile.am` plugin rules. **No configure work was needed**: the tree
      already requires `ext2fs >= 1.47.3-wc2` when utils and ldiskfs are both
      enabled, which is the WhamCloud fork and covers both `dirdata` and
      `ext2fs_xattrs_read_inode()`
- [x] `Documentation/man3/llapi_scan_device.3`
- [x] `llapi_scan_device_test`, and the oracle as **conf-sanity test_165**
      rather than a `sanity` test — a mounted MDT has objects still in the
      journal, so a client-visible FID can be legitimately absent from the
      device and the test would be flaky
- [x] Validated against a synthetic MDT image: same 18 FIDs and the same
      class counts as the prototype scanner, all 7 contract tests passing,
      identical record set at 1/2/4/8 threads
- [ ] **File the two tickets, Components set: llapi, utils.** The local
      commit is tagged **LU-20462**, the epic, because the technical task
      does not exist yet; re-tag it before pushing
- [ ] `lfs find --device` — the consumer, second change of the series
- [ ] Rebuild an ldiskfs lab (`tests/lab-scan/`, stages 01→04) and run
      test_165 against a real MDT before pushing

---

## Paste into Jira (wiki markup)

Jira renders wiki markup, not Markdown: {{*bold*}} is single asterisks,
{{{{monospace}}}} replaces backticks, and a line *starting* with {{*}} becomes a
bullet — so emphasis at the start of a line uses an {{h5.}} heading instead.

```
{{llapi_scan_device()}} produces the same per-object records as
{{llapi_scan_namespace()}} (LU-20603), reading an MDT or OST *directly from
the block device* with libext2fs instead of walking a mounted namespace from
a client.

It needs no kernel change, no server modification and no mount, so it runs
against existing servers and against a snapshot or a passive failover
partner.  It follows e2scan and Lester, the Lustre Lister.  The device is
opened read-only and there is no write path: LFU reads, LFSCK and OI Scrub
repair.

h5. Why it is worth a second producer
A client-side namespace walk costs an RPC round trip per object.  Reading the
inode table costs a sequential device read.  Measured on a 20M-object MDT on
NVMe, a cold full scan ran at 1.44M objects/s, 94% of the device's bandwidth,
flat in thread count because the device saturates before the scanner does.
On a 1024-byte MDT inode every Lustre xattr is inline, so the FID, layout,
SOM size and linkea come back with the inode: the measured external-EA-block
rate on a real MDT was 0.0%.

h5. One record, two producers
{{struct llapi_scan_rec}} is versioned by {{sr_size}} and carries a validity
mask, so a field a producer cannot answer for is distinguishable from one
that is genuinely zero.  A device scan fills a different subset of the same
record, and the consumers queued behind LFU should not have to care which
producer filled it.  The record grows {{sr_projid}}, {{sr_parent_fid}}, the
raw linkea, the object id, the LMA flags and an object class; fields are only
ever appended.  {{LLAPI_SCAN_LAZY_SIZE}} needs nothing new -- {{trusted.som}}
is exactly what that bit already means.

h5. libext2fs stays out of liblustreapi
The ldiskfs half builds as {{scan_ldiskfs.so}} and is {{dlopen}}ed on first
use, the way {{mount.lustre}} loads {{mount_osd_ldiskfs.so}}; a client build
has no plugin and the call returns -ENOTSUP.  Only a {{--disable-plugins}}
server build links libext2fs into the library, and that build already links
it into {{mount.lustre}}.

h5. What a device scan does not have
Paths.  It recovers names and parent FIDs from the linkea; resolving those
into a path is an Output Format concern and is priced separately.  The record
says so through its validity mask rather than returning an empty string.

h5. What it sees that a namespace walk does not
Internal objects, OST data objects, HSM agent inodes and orphans.  Each
record carries its class, and the default is to emit only namespace-visible
objects, so a consumer that deletes things does not have to know the OI file
layout to avoid eating one.  Three internal objects still classify as visible
because LMA alone cannot identify them -- LU-20602 is the durable fix; until
it lands the man page says so.

h5. Consistency
The scan does not lock and does not coordinate with the MDS.  It sees a
stale, un-replayed view, which is the right trade for a scan of this kind,
and it detects and skips objects caught mid-update rather than emitting them
wrong: measured at 0.05% of allocated inodes under sustained creates and zero
on a quiescent target.  The count comes back to the caller, because an API
that drops objects silently is not one a space-accounting consumer can build
on.

h5. Acceptance
Against a mounted, serving MDT, the scanner's FID set contains every FID
{{lfs find}} reports from a client -- zero misses, the property that matters
for a scanner a cleanup tool will act on.  Extras are expected and bounded:
the {{.lustre}} pseudo-directories and the three objects of LU-20602.

h5. Scope
The ldiskfs backend and the call that reaches it.  Checkpoint and restart,
rate limiting, the ZFS backend behind the same call, and the Object Stream
serialization are each separate.  The record stays in-memory: the wire format
LU-20462 will send is still being chosen, and nothing here should freeze it.
```
