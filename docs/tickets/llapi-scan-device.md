# LU-20606: device scanner behind `llapi_scan_device()`

**Filed 2026-08-18 as LU-20606 — by Andreas Dilger, not by us.** Technical
task, Open, **parent LU-20462**, related to **LU-20605**, assigned to Hiroshi
Nishida, Affects Version 2.18.0, Major/Severity 3. Also relates to **LU-20602**
(internal objects LMA cannot identify) and **LU-20603**
([`llapi-scan-api.md`](llapi-scan-api.md)), the record it emits. Step 3 of
[`architecture.md`](../architecture.md) §12 — the first real performance win,
and the first piece that runs on a server.

**Its description is our own `design-ldiskfs-scanner.md` §1**, lightly edited:
purpose, in scope, out of scope, why this module first. Worth knowing for two
reasons. The design document is being read upstream, so what it claims is what
we will be held to; and the ticket therefore scopes the **whole module**, not
the first change — see *What the first change covers* below.

Design of record: [`design-llapi-scan-device.md`](../design-llapi-scan-device.md).
Mechanism and measurements: [`design-ldiskfs-scanner.md`](../design-ldiskfs-scanner.md).

The LU project defines no components, so that field stays empty here as it is
on every other ticket in the project.

**One change under this ticket**, pushed on top of 68094/68095:
`llapi_scan_device()` and its plugin. The consumer went the other way in the
end — see [`lfind.md`](lfind.md). Putting both here was the earlier plan and
building it settled the argument against: LU-20606's own *In scope* list is the
module, "driven by a caller-supplied mask", and a command is a caller; two of
the consumer's four changes touch `lfs` and the namespace side of
`liblustreapi`, whose proof is `sanity` 56\* and has nothing to do with
scanning a device.

---

## What the first change covers, and what it does not

LU-20606's *In scope* list is the module. The first change is most of it:

| LU-20606 says | First change |
|---|---|
| Full-device enumeration of ldiskfs inodes on an MDT or OST | **yes** |
| FID recovery and object classification from Lustre xattrs | **yes** — `sr_fid`, `sr_class`, `sr_lma_*` |
| Attribute extraction driven by a caller-supplied mask | **yes** — `sp_want` |
| Parallel scan within one device | **yes** — `sp_thread_count`, chunked, private handles |
| Pushed-down filter evaluation, ordered by I/O cost | **partly** — `sp_filter` runs on the object before any xattr is read, which is the ordering; a *compiled* filter pushed into the scan is not there |
| Checkpoint and restart | **no** — `sr_ino` is the value a checkpoint would be expressed in, and that is all |
| Object Stream | **no, on purpose** — the record is in memory; the serialization is still open between FlatBuffers and Cap'n Proto |

Say this on the ticket rather than let it be inferred: the change is not the
whole task, and the two gaps are deliberate.

## The change's own text

Not a ticket description any more — LU-20606 has one. This is the commit
message's argument, kept here as the source text, and the basis of the comment
at the end of this file.

**Summary:** llapi: scan an ldiskfs target directly


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

## The consumer, moved to its own ticket

`lfind(8)` and the two refactors under it are drafted in
[`lfind.md`](lfind.md). What follows is kept as the text that draft came from.

## Second change (`lfind(8)`)

### Summary

utils: lfind, find over a scan of a target

### Description

`lfind(8)` runs `lfs find`'s predicates against `llapi_scan_device()` on a
server: a target's own objects, read off the device, with no mount and no MDS.

**Not a mode on `lfs find`**, which was the first plan. That command is a
client command by construction — `llapi_is_lustre_mnt()` requires `":/"` in the
mount's device name, so a server target mount is deliberately not recognised
and `lfs find` answers `-ENODEV` on a server with no client mount. A device
scan is disk-reading, root-only, path-less and one-target; that is a different
tool, not a flag. And `lfs` ships in `lustre-client` while the scan plugin does
not, so the flag would have answered `-ENOTSUP` on every client install.

The predicate vocabulary is still shared, and with no new API: the option table
and getopt loop move out of `lfs_find()` into a source file compiled into both
binaries, the way `callvpe.c` is already compiled into both `lfs` and
`lustre_rsync`. One table, two commands, nothing exported, no ABI touched.
`lfind` installs under `if SERVER`, so it exists only where it can run.

The target is named three ways: `--device` for a block device, image or
snapshot, which always works; `--target testfs-MDT0000` for a target mounted on
this node; and `--local` for every target the node serves. The name is the
superblock label `mkfs.lustre` wrote, not a mountpoint — a path argument to
`lfs find` already means *walk this namespace*.

`--target` and `--local` both resolve through `osd-*/*/mntdev`, a read-only
attribute of a mounted OSD, so they see what is mounted here and nothing else;
an unmounted target, a snapshot or an image has no name to look up and needs
`--device`. `--local` takes the MDTs and OSTs and skips the MGS, which holds
configuration llogs and no FID-bearing objects; it scans one target at a time,
since one scan already runs at the device's bandwidth; and a target that fails
is reported and the sweep continues, with a non-zero exit if any failed, so a
partial sweep cannot be mistaken for a complete one.

Four differences the mode has to make explicit, each a place behaviour is not
preserved:

- **One invocation covers one target.** Under DNE that is a fraction of the
  namespace, with nothing to say so; the complete answer is a scan per target,
  merged, and the merge is not this module's.


- Output is the FID, because a device scan has no paths. A `-printf` format
  asking for one is refused at parse time rather than printing blank.
- A predicate the target cannot answer is refused before the scan starts, not
  answered "no matches" — the two are indistinguishable to a user.
- Root only, MDT-only, and no access control whatsoever. `--size` on a striped
  file is `trusted.som`'s answer or none, which is `--lazy` semantics by
  construction.

**Acceptance:** the `sanity.sh` 56\* series stays green. It is the whole proof
that factoring the parser out of `lfs_find()` changed nothing.

**Known cost, found while building the first change.** LU-20605 rebuilt only
the *front* half of `cb_find_init()`. The deciding half still reads
`param->fp_lmd` directly, and the OST glimpse rewrites it in place, so a device
record cannot simply be handed to it: either the record is presented as an
`lmd` — with the raw on-disk LOV byte-swapped, since the ioctl path delivers a
swabbed one — or that half moves onto the record first, which is LU-20605's
second half and a change of its own. The second option is the honest one and
the more expensive; decide before starting.

**Name:** glibc has `lfind(3)`, so `man lfind` finds that one and ours needs
`man 8 lfind`. Kept because the prototype, its man page and every document here
already say `lfind`; `lfsscan` is the alternative if a reviewer objects.

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
- [x] Multi-agent review (2026-08-19): eight findings, all fixed in place —
      `scan_ldiskfs.so` packaged in `lustre.spec.in`; the label parser now
      takes `-`, `:` and `=` (a writeconf'd or never-mounted OST scanned as
      an MDT and returned nothing); xattr read failures now skip and count
      the object instead of misclassifying it or passing the MDT size as
      authoritative; `sr_attr_flags` masked to the five bits that really
      are `STATX_ATTR_*` (htree dirs reported AUTOMOUNT); `sr_mdt_index`
      gated on a parsed MDT label, not any label; a `pthread_create`
      failure degrades to fewer workers instead of returning an error after
      a complete scan; the `sp_stats` header comment scoped to the device
      scan; test_165 checks the scanner's exit status, not `sort`'s
- [x] Default emission follows the target's role: an OST scan would have
      returned nothing, since every object on an OST is a data object and
      the policy emitted only the namespace-visible class. conf-sanity
      test_165 now runs the contract against an OST as well
- [x] The ticket exists: **LU-20606**, filed by Dilger on 2026-08-18. The
      local commit is re-tagged to it
- [ ] Post the comment at the end of this file, so the ticket says what the
      change does and does not do
- [ ] LU-20603's and LU-20605's descriptions still carry the Markdown
      asterisks from their first paste
- [x] `lfind(8)` — the consumer, built as three commits: the deciding half of
      `cb_find_init()` split out, the predicate parser shared into
      `lfs_find_parse.c`, and `llapi_find_device()` under it
- [x] Man page said "since release 2.19.0"; master is 2.17.56, the series that
      becomes **2.18.0**, and userspace tools target 2.18. Fixed in all three
      pages, including the one already on Gerrit as 68094
- [ ] Rebuild an ldiskfs lab (`tests/lab-scan/`, stages 01→04) and run both
      **`sanity` 56\*** (the refactor's proof) and **conf-sanity test_165**
      (the scanner's) before pushing. Neither has ever run
- [ ] File the `lfs find` bug the refactor uncovered: a bad `--comp-flags` or
      `--mirror-state` prints its error and exits 0

---

## Comment to post on LU-20606

The description is Dilger's and is fine. What the ticket does not say is what
the change does, what it deliberately leaves out, and that the acceptance
criterion has now been met on a real MDT.

Written for the rich-text editor: no double hyphens, no asterisks, no braces —
the markup that mangled LU-20611's description twice.

~~~
llapi_scan_device() reads an MDT's or OST's objects off the device with
libext2fs and delivers the same per-object records llapi_scan_namespace()
(LU-20603) does. One contract, two producers: a device scan fills a
different subset of it rather than inventing a second record, so the
consumers queued behind LFU need not care which producer filled it.

h5. libext2fs stays off liblustreapi
The backend builds as scan_ldiskfs.so and is dlopened on the first scan,
the shape mount.lustre already uses for mount_osd_ldiskfs.so, so a client
build has no plugin and the call answers ENOTSUP. No configure work was
needed: the tree already requires ext2fs 1.47.3-wc2 wherever utils and
ldiskfs are both enabled.

h5. Against the In scope list
Enumeration, FID recovery and classification, mask driven attribute
extraction and parallel scan within one device are in this change. Filter
evaluation is pushed down as far as the ordering goes, the caller's filter
running before any xattr is read, but a compiled filter is not there and
neither is checkpoint and restart. The Object Stream is deliberately out:
the record is in memory, and the serialization is still open.

h5. Verified on a real MDT
conf-sanity test_165: scanned 108 objects and found all 102 visible FIDs,
zero misses. The six extras are the .lustre entries and the three internal
objects of LU-20602. The contract tests pass 7 of 7 against an MDT and 7
of 7 against an OST, and the same scan run at 1, 2, 4 and 8 threads
delivers an identical object set.

h5. One question
The record now carries HSM state, sr_hsm_states and sr_hsm_archive_id,
because PCC-RO and tiered storage need it and neither producer had it. It
is in 68094 at patchset 3, so the shape is cheap to change now and an ABI
event once that lands. Does it look right to you?
~~~

The TLU-219 question is answered: the ticket owner supplied the export on
2026-08-19, and the read-up sits in `docs/local/` since it is TLC tracker
material. What we say back about it belongs on **LU-20462**, where the format
decision lives, rather than here.
