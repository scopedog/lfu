# `llapi_scan_device()` — the device scanner behind the same record

**Date:** 2026-08-19 · **Depends on:** LU-20603 (`llapi_scan_namespace()`) ·
**Realizes:** [`architecture.md`](architecture.md) §12 step 3, whose mechanism
is [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) ·
**Ticket:** **LU-20606** ([`tickets/llapi-scan-device.md`](tickets/llapi-scan-device.md)),
filed 2026-08-18 by Andreas Dilger with `design-ldiskfs-scanner.md` §1 as its
description

Plan of record for landing the ldiskfs device scanner upstream. The scanner
itself is designed and measured elsewhere; this document is only about the
shape it takes in the tree — the API it presents, how libext2fs stays out of
the client library, and what the record has to grow.

Written against `../lustre-lu20603` @ `1e706d95f9` (the LU-20603/LU-20605
series as pushed) and the prototype at `src/lfu_scan_ldiskfs.c`.

---

## 1. What lands

```c
int llapi_scan_device(const char *device, const struct llapi_scan_param *sp,
		      llapi_scan_cb_t cb, void *data);
```

Same record, same callback, same parameter struct as `llapi_scan_namespace()`.
The only difference is where the objects come from: a block device, image or
snapshot read directly with libext2fs, instead of a mounted namespace walked
from a client.

Two stacked changes, as LU-20603/LU-20605 were:

| | Change | Contents |
|---|---|---|
| P1 | `llapi_scan_device()` | the API, the ldiskfs plugin, `Documentation/man3/llapi_scan_device.3`, `llapi_scan_device_test`, the conf-sanity oracle |
| P2 | the consumer | `lfind(8)`, the predicate parser factored out of `lfs.c`, `Documentation/man8/lfind.8` |

Both under LU-20606, whose own description scopes the whole module rather than
either change — §11 says which parts of that scope each one carries.

**Why one record and not a second one.** `struct llapi_scan_rec` is already
versioned by `sr_size` and carries `sr_valid`, so a field the producer could
not answer for is distinguishable from one that is genuinely zero. That was
written for exactly this second producer. A device scan answers a *different
subset* of the same record — not a different record — and the consumers queued
behind LFU (PCC-RO cleanup, Trash Can, FLR/EC resync, HSM) should not care
which producer filled it in.

---

## 2. Why a plugin, and not a link

`liblustreapi` is the client library. It ships in `lustre-client`, it is linked
by every consumer of the API, and it must not acquire a dependency on
libext2fs.

Upstream already solved this once. `mount_utils.c:517` `load_backfs_module()`
`dlopen`s `${pkglibdir}/mount_osd_ldiskfs.so`, built only under
`if PLUGINS / if LDISKFS_ENABLED` (`lustre/utils/Makefile.am:222-236`), and
resolves its ops table with `dlsym()` through the `DLSYM()` macro. The same
file falls back to `$LUSTRE/utils/mount_%s.so` so an uninstalled build tree
works under test-framework. The device scanner mirrors that, file for file:

```
lustre/utils/liblustreapi_scan_device.c   llapi_scan_device(), ops table, dlopen
lustre/utils/libscan_ldiskfs.c            libext2fs: open, chunked scan, xattrs
                                          -> scan_ldiskfs.so   (PLUGINS)
                                          -> libscan_ldiskfs.a (no PLUGINS)
```

The build matrix, which is the whole argument:

| Build | `PLUGINS` | `LDISKFS_ENABLED` | libext2fs on `liblustreapi`? | `llapi_scan_device()` |
|---|---|---|---|---|
| client (default) | yes | no | **no** | `-ENOTSUP` |
| server | yes | yes | **no** — `dlopen` at first call | works |
| server `--disable-plugins` | no | yes | yes, statically | works |
| client `--disable-plugins` | no | no | **no** | `-ENOTSUP` |

Only row 3 puts libext2fs on the library, and that build already puts it on
`mount.lustre`. The one deliberate divergence from `load_backfs_module()`: it
prints nothing when a plugin is missing ("do not clutter up console with
missing types"), whereas a scan that cannot load its backend must fail loudly —
`-ENOTSUP` from the call and a `llapi_error()` naming the file it looked for.

---

## 3. What a device scan can fill in

Per-field, against `include/lustre/lustreapi.h` as landed. Tier numbers are
[`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) §6 — tier 0 is the
inode, tier 1 an inline xattr, tier 2 an external EA block.

| Field | Device source | Tier | Notes |
|---|---|---|---|
| `sr_fid` | `trusted.lma` → `lma_self_fid` | 1 | always read: classification needs it |
| `sr_mode`, `sr_nlink` | `i_mode`, `i_links_count` | 0 | |
| `sr_uid`, `sr_gid` | `i_uid`+`i_uid_high`, `i_gid`+`i_gid_high` | 0 | |
| `sr_size_bytes` | `i_size` | 0 | **the target's own size**, not the file's |
| `sr_blocks` | `i_blocks_lo`+`l_i_blocks_high` | 0 | likewise |
| `sr_atime`/`mtime`/`ctime`/`btime` | inode + `*_extra` | 0 | |
| `sr_attr_flags` | `i_flags` | 0 | ext4's bits are `STATX_ATTR_*`'s for all five names LFU supports |
| `sr_lmm`, `sr_lmmsize` | `trusted.lov` | 1–2 | raw, as on the namespace side |
| `sr_lmv`, `sr_lmvsize` | `trusted.lmv` | 1–2 | raw |
| `sr_mdt_index` | superblock label `s_volume_name` | 0 | `fsname-MDT0000`, as `ldiskfs_label_read()` reads it; one value for the whole scan, and it also settles MDT vs OST (§5.1) |
| `sr_path` | **never** | — | see below |
| `sr_name` | `trusted.link` first entry | 1–2 | a name, not a path |
| `sr_parent_fd`, `sr_fd` | **never** | — | always −1; nothing is mounted |

**`sr_path` is the honest gap.** A device scan recovers *names and parent
FIDs*, not paths: resolution is a separate walk up the linkea chain and, per
`architecture.md` §7, priced separately as an Output Format concern. A consumer
that needs paths either resolves them itself from what the record carries or
uses the namespace producer. The record says which by leaving the bit clear —
that is what `sr_valid` is for.

### 3.1 Fields the record grows

Appended, never inserted; `sr_size` and `sr_valid` make this safe.

| New field | Bit | Why |
|---|---|---|
| `sr_projid` | `LLAPI_SCAN_PROJID` | tier 0 on the device, and **missing from the record today** although `lfs find --projid` exists — the namespace producer fills it too, so this is a fix for both |
| `sr_parent_fid` | `LLAPI_SCAN_PARENT` | linkea's first parent; the input to path resolution |
| `sr_linkea`, `sr_linkeasize` | `LLAPI_SCAN_LINKEA` | raw `trusted.link`, handed over like `sr_lmm` — every hardlink's parent and name, which one `sr_name` cannot carry |
| `sr_ino` | `LLAPI_SCAN_INO` | the backend object id; what a checkpoint and a restart are expressed in |
| `sr_lma_compat`, `sr_lma_incompat` | `LLAPI_SCAN_LMA` | `LMAC_*` / `LMAI_*`; how a consumer sees "orphan", "remote parent", "dead" |
| `sr_class` | `LLAPI_SCAN_CLASS` | §5 classification: visible, internal, OST object, agent, no-LMA, bad |

`LLAPI_SCAN_LAZY_SIZE` and `LLAPI_SCAN_LAZY_BLOCKS` need nothing new. They
already mean "this size is a lazy one", which is precisely what `trusted.som`
answers with on the MDT, and the striped-file rule is the same rule LU-20605
had to carry over for `--lazy`. One bit, one meaning, two producers — the
useful sign that the contract generalizes rather than being bent.

### 3.2 One bug to fix on the way in

```c
/* lustre/utils/lustreapi_internal.h, as landed */
#define LLAPI_SCAN_ALL_MASK	((LLAPI_SCAN_LAZY_BLOCKS << 1) - 1)
#define LLAPI_SCAN_MDT_MASK	(LLAPI_SCAN_ALL_MASK & ~LLAPI_SCAN_DIRENT_MASK)
```

`ALL_MASK` is "every bit up to the last one defined", so appending §3.1's bits
after `LAZY_BLOCKS` silently drags them into `MDT_MASK` — the set
`llapi_scan_rec_gather()` treats as *answered by the MDT ioctl*. The namespace
producer would then claim to have filled `sr_linkea`. Fix it in P1 by pinning
`ALL_MASK` to a named last namespace bit, or by enumerating `MDT_MASK`
explicitly. It is an internal header: no ABI cost, and no reason to leave a
tripwire behind.

---

## 4. `sp_want` and `sp_filter` on a device

`sp_want` is a demand mask, and on a device it maps straight onto the xattr
reads the scanner would otherwise do unconditionally — the prototype's
`cx->needs`:

| `sp_want` bit | xattr read |
|---|---|
| `LLAPI_SCAN_LAYOUT` | `trusted.lov` |
| `LLAPI_SCAN_LMV` | `trusted.lmv` |
| `LLAPI_SCAN_LAZY_SIZE`, `LLAPI_SCAN_LAZY_BLOCKS` | `trusted.som` |
| `LLAPI_SCAN_NAME`, `LLAPI_SCAN_LINKEA`, `LLAPI_SCAN_PARENT` | `trusted.link` |
| `LLAPI_SCAN_FID`, `LLAPI_SCAN_CLASS`, `LLAPI_SCAN_LMA` | `trusted.lma` — read regardless |

`sp_want == 0` keeps meaning *everything*. On the namespace side that carries
one exception, `LLAPI_SCAN_MDT_INDEX`, because it costs an open per regular
file. No device field earns a matching exception: on a 1024-byte MDT inode
every Lustre xattr is inline, **measured tier-2 rate 0.0%** on a real MDT
(`design-ldiskfs-scanner.md` §17), and the cost of a spill is a property of the
individual object, not of the field asked for.

`sp_filter` is "the cheap stage", and each producer defines what that is. On
the namespace side it is the dirent, before any ioctl. On the device side it is
**tier 0** — the whole inode, before any xattr is touched. So `sp_filter` sees
mode, nlink, uid, gid, projid, size, blocks, times and flags, with `sr_fid`
*absent*, and returning 1 skips the object with no xattr work at all. That
ordering is not a nicety: the prototype's suite asserts 17 of 18 objects are
rejected before classification when one matches, and the kernel-side measurement
found a rejecting tier-0 filter to be *faster than no filter at all*
(`measurements/filter-pushdown-measured-2026-08-17.md`).

The valid-bit discipline makes this safe to state in one line in the man page:
a pre-filter record carries `sr_valid & LLAPI_SCAN_TIER0_MASK`, and a consumer
that tests anything else is testing a bit it can see is clear.

---

## 5. Objects a namespace walk never sees

A device scan enumerates the whole inode table, so it finds what `lfs find`
cannot: internal objects (OI files, the CATALOGS, quota files, `lost+found`),
OST data objects on an OST, HSM agent inodes, and orphans with `nlink == 0`.

`sr_class` reports which, and the default is to emit **only the target's own
subject matter** — everything else is counted and held back unless
`LLAPI_SCAN_F_INTERNAL` says otherwise. A consumer that deletes things must not
have to know the OI file layout to avoid eating it.

**What that subject matter is depends on the target, and the first cut got it
wrong.** The policy was "emit `LLAPI_SCAN_CLS_VISIBLE`", which is right on an
MDT and empty on an OST: an OST has no namespace, every object on it is a data
object, and the scan would have returned nothing at all while reporting
success. The default now follows the target's role, which the backend reads
from the label at open time — visible on an MDT, `CLS_OST_OBJ` on an OST.
Found by asking what `--local` does on an OSS (§9.1); it would have been found
otherwise by a very confused operator.

Three internal objects still leak: LMA alone cannot identify them
(`design-ldiskfs-scanner.md` §5.1b, filed upstream as **LU-20602** for the
durable fix). Measured, that is 3 extras against a client oracle at both 173
and 509 objects — constant, not proportional. The man page says so rather than
implying the classification is complete.

---

## 6. Telling the caller what was skipped

The namespace producer either delivers an object or fails. A device scan
silently drops things by design: a torn read is detected and skipped rather
than emitted wrong (**0.05% worst case under sustained creates, 0 quiescent** —
`design-ldiskfs-scanner.md` §8.2). An API that drops without saying so is not
one a space-accounting or a deleting consumer can build on.

So P1 adds an optional out-parameter, filled on return:

```c
struct llapi_scan_stats {
	__u32	ss_size;
	__u64	ss_seen;	/* inodes examined */
	__u64	ss_emitted;	/* records delivered to the callback */
	__u64	ss_skipped;	/* failed validation — torn reads, mostly */
	__u64	ss_filtered;	/* rejected by sp_filter */
	__u64	ss_class[LLAPI_SCAN_CLASS_MAX];
};
```

reached as `sp_stats` in `llapi_scan_param` (a pointer, appended, zero means
"do not care"). The namespace producer fills the fields it knows, which keeps
one struct for both.

---

## 7. Parallelism

`sp_thread_count` already exists and its contract already says the callback may
be called from several threads and must be thread-safe. The device side reuses
it verbatim. Underneath it is the prototype's chunked scan: a chunk is enough
block groups to cover ~64K inodes, workers take chunks from a shared cursor
(not equal slices — allocation is sparse and clustered), and **each worker opens
its own `ext2_filsys`, because libext2fs is not thread-safe**. Measured at
1.44M objects/s cold, 94% of the device's bandwidth, flat in thread count
because the device saturates first.

---

## 8. What libext2fs has to be — already settled upstream

Two requirements, and the tree already carries both:

```m4
# config/lustre-core.m4:4341 — lustre/utils/llverfs.c libmount_utils_ldiskfs.c
AS_IF([test "x$enable_utils" = xyes -a "x$enable_ldiskfs" = xyes], [
	PKG_CHECK_MODULES([EXT2FS], [ext2fs >= 1.47.3-wc2])
])
```

`1.47` is where `ext2fs_xattrs_read_inode()` appears, and **`-wc2` is the
WhamCloud fork**, whose `EXT2_LIB_FEATURE_INCOMPAT_SUPP` includes
`EXT4_FEATURE_INCOMPAT_DIRDATA`. A build that can build ldiskfs utils can
therefore build and run this scanner, and **no new configure check is
needed** — `if LDISKFS_ENABLED` is the whole condition. This replaces the
`AC_CHECK_LIB` this document planned; the check was already there, one layer
up.

What survives is the *runtime* case: a build machine with the fork and a
scan host without it. `ext2fs_open()` fails `EXT2_ET_UNSUPP_FEATURE`, which
the backend maps to `-ENOTSUP` so the library can name the cause rather than
pass an errcode string out. Every other errcode below `EXT2_ET_BASE` is a
plain errno and is returned as one, so a device that is not there says
`ENOENT` instead of arriving as an I/O error.

## 9. The consumer: `lfind(8)`, and why not `lfs find --device`

**Decided 2026-08-19, against this document's first answer.** The device scan
gets its own server-side command, and shares `lfs find`'s predicate vocabulary
by compiling the parser into both rather than by copying it.

### 9.0 Why not a mode on `lfs find`

The first plan was `lfs find --device`, on the argument that `lfs.c` already
parses every predicate and LFU is meant to replace that command rather than sit
beside it. Two facts kill it.

**`lfs find` is a client command by construction, not by convention.** It walks
a client mount and upstream takes care that a server target mount does not look
like one:

```c
/* Is this a lustre client fs? */
int llapi_is_lustre_mnt(struct mntent *mnt)
{
	return (llapi_is_lustre_mnttype(mnt->mnt_type) &&
		strstr(mnt->mnt_fsname, ":/") != NULL);
}
```
— `liblustreapi.c:3955`, and `get_root_path()` skips everything that fails it
(`liblustreapi_root.c:222`). An MDT mounted at `/mnt/testfs-mdt0` *is* fstype
`lustre` in `/proc/mounts`, but its device is `/dev/vdb`, not
`mgs@tcp:/testfs`, so it is deliberately excluded. On a server with no client
mount, `lfs find` returns `-ENODEV`. Everything about the command is
path-in/path-out, whole-filesystem, ordinary-user. A device scan is
disk-reading, root-only, path-less, one-target and MDT-only: not a mode of that
command, a different tool wearing its name.

**And the flag would be dead where the command mostly lives.** `%{_bindir}/lfs`
ships in the shared file list of a spec that builds either `lustre` or
`lustre-client` (`lustre.spec.in:137`), so `lfs` is on every client. The scan
plugin is not: a client build has no `scan_ldiskfs.so`. `lfs find --device`
would be a documented flag that answers `-ENOTSUP` on every client install in
existence.

### 9.0b One vocabulary, two commands, no exported ABI

The one good argument for the mode was avoiding a second copy of the predicate
table — `lfs_find()` is ~1,077 lines, most of it the `getopt_long()` loop that
fills `struct find_param`, and the prototype's own reimplementation of that
vocabulary is exactly the drift risk to avoid.

Sharing it needs no API and no ABI. `callvpe.c` is already compiled into both
`lfs` and `lustre_rsync` (`Makefile.am:75,81`), and `lfs.c` already includes
`lustreapi_internal.h`, where `struct find_param` lives. So the parser moves
into a source file compiled into both binaries:

```
lustre/utils/lfs_find_parse.c   the option table and the getopt loop
lustre/utils/lfs.c              lfs find      — behaviour unchanged
lustre/utils/lfind.c            lfind(8)      — the same predicates, on a target
```

No new exported symbol, no internal structure leaking into the library's ABI,
and one table to change when a predicate is added. **`sanity.sh` 56\* is the
proof obligation**: the refactor must leave `lfs find` bit-identical.

`lfind` is installed under `if SERVER`, beside `mkfs.lustre` and
`tunefs.lustre`, so it exists only where it can run.

**Name collision, flagged rather than settled.** glibc has `lfind(3)` — a
linear-search function, documented on the `lsearch(3)` page — so `man lfind`
resolves to that and ours needs `man 8 lfind`. The prototype, its man page
(`Documentation/man8/lfind.8`, already written in upstream's style) and this
project's documents all say `lfind`, which is why it stands; a reviewer who
objects has a fair point, and `lfsscan` is the obvious alternative.

### 9.1 Naming the target

Three spellings, because a device path is the only handle that always exists
and the worst one for the everyday case:

| | Means | Works when |
|---|---|---|
| `--device /dev/vdb` | this block device, image or snapshot | always — nothing has to be mounted, no Lustre module loaded |
| `--target testfs-MDT0000` | the target of that name on this node | it is mounted here (see below) |
| `--local` | every Lustre target this node serves | same, and it is the real administrative command |

The target name is the one `mkfs.lustre` wrote into the superblock label, not a
mountpoint: `testfs-MDT0000`, never `/mnt/testfs-mdt0`. A path argument to
`lfs find` already means *walk this namespace*, so a mountpoint is not accepted
as a way of naming a target — one argument, one meaning. `--device`,
`--target`, `--local` and a path are mutually exclusive; two of them is a usage
error, not a merge.

Whichever spelling is used, the scan reads the label anyway and reports the
target it actually opened, so `--device` never leaves you guessing which MDT
you got.

#### How the name resolves

`osd-ldiskfs.<target>.mntdev` is a read-only attribute of a mounted OSD
(`lustre/osd-ldiskfs/osd_lproc.c:161`), and `osd-zfs` publishes the same. So
the lookup is a parameter read, not a `/proc/mounts` parse and not a forked
`lctl`:

```c
llapi_param_get_paths("osd-*/*/mntdev", &paths, 0);   /* every local target */
llapi_param_get_value(paths.gl_pathv[i], &buf, &len); /* its device */
```

The target's name is the path component before `mntdev`, which is what makes
one call serve both flags: `--target` filters the glob, `--local` takes all of
it.

Three consequences worth stating rather than discovering:

- **`--target` needs the target mounted here.** The attribute exists only while
  the OSD is up. An unmounted target, a snapshot, a failover partner's LUN and
  an image have no name to look up, and `--device` is the only way in. The
  error for a name that does not resolve says so, rather than reporting the
  target as missing.
- **`--local` sees what is mounted, and nothing else.** A target this node
  could serve but currently does not is invisible to it, by construction. That
  is the right behaviour — but it means `--local` is not "everything on this
  machine's disks", and the man page should not let anyone read it that way.
- **The parameters are world-readable and the devices are not.** A non-root
  `--local` therefore resolves every target and then fails to open each one.
  It must report that per target, loudly, and never quietly deliver an empty
  result: the difference between "no matches" and "you are not root" is the
  whole point of §9.2's second rule.

#### It runs on a server

`--local` is a property of the *node*, not of a target: an MDS or an OSS, the
machine that serves the disks. On a client there is no OSD, the parameter does
not exist, and the flag must say **"no local Lustre targets"** and exit
non-zero rather than report an empty scan — the same rule as everywhere else
here. The client already has the command for its question: `lfs find /mnt/fs`,
walking the namespace over RPCs.

A node can be both, and often is in a test setup: a client mounted on an MDS.
There `--local` still means *the targets this node serves*, not the filesystem
it happens to have mounted. Two different questions from one machine, and the
flag answers only one of them.

#### What `--local` includes

Every local target whose label names an MDT or an OST, and nothing else.

- **The MGS is skipped.** A standalone MGS is an OSD device too and answers the
  same parameter, but it holds configuration llogs, not FID-bearing objects.
  Scanning it would produce a page of internal objects and no useful records.
- **A combined MGS/MDT is scanned once.** It is one device with one label
  (`testfs-MDT0000`); if two parameters ever resolve to the same device, the
  device is scanned once.
- **A ZFS target resolves and then refuses, by name.** `osd-zfs` publishes
  `mntdev` as well, so `--local` on a ZFS server finds its targets and has no
  backend for them yet: the honest answer is `-ENOTSUP` naming the target, not
  a silent omission from the sweep. When the ZFS backend lands behind the same
  call, `--local` picks it up with no change here.

#### One target at a time

`--local` scans its targets **sequentially**, and `sp_thread_count` parallelism
stays *within* a target. A single scan already runs at the device's bandwidth —
1.44M objects/s, 94% of an NVMe stripe, flat in thread count — so scanning
eight OSTs at once would divide the same CPU and thrash whatever cache the
underlying storage shares. Sequential also keeps the failure story simple: a
target that fails is one line in the output at the point it failed.

**A failed target does not end the sweep.** It is reported, the scan continues
with the next one, and the exit status is non-zero if any target failed — so a
script that checks the status cannot mistake a partial sweep for a complete
one. This is the same rule as §6: an answer that quietly omits things is worse
than an error.

#### One invocation, one filesystem's worth of one node

Under DNE the objects of a single MDT are a fraction of the namespace: a
striped or remote directory puts its children on another MDT, and a scan of
this one returns fewer results with no indication that anything is missing.
`--local` narrows that gap on a node holding several MDTs and does not close
it — the complete answer is a scan per target across every server, merged, and
cross-target merge is a server-side Filter Rule concern (`architecture.md` §1),
deliberately not this module's.

What makes the merge possible at all is that every record already carries
`sr_mdt_index`, read from the label at open time, so records from several
targets stay attributable once concatenated. FIDs are unique across the
filesystem, so a merged FID list needs no deduplication — but a *count* does,
and that is where the merge stops being concatenation.

### 9.2 Where `lfind` differs from `lfs find`

Same predicates, three differences, and each is a place a reviewer will look:

1. **Output.** There are no paths, so the default is the FID. `-printf` keeps
   working for everything the record carries; a format asking for `%p` is
   refused at parse time, not silently blank. Being a separate command is what
   makes this clean rather than a surprise: nobody expects `lfind` to print
   what `lfs find` prints.
2. **Predicate refusal.** A predicate the target cannot answer is refused
   *before the scan*, not answered "no matches" — the prototype's
   `can_supply` / `missing_fields` mechanism, which exists precisely because
   the two are indistinguishable to a user. Nothing in the current vocabulary
   is actually unanswerable on an ldiskfs MDT, so this is a guard for the ZFS
   and kernel-ring backends that follow.
3. **Privilege and semantics.** Root, one target, an MDT-only view (so
   `--size` on a striped file is SOM's answer or none, which is `--lazy`
   semantics by construction), and no access control whatsoever. The man page
   has to say that in those words.

`lfs find` itself changes in exactly one way: its predicate parsing moves to a
file also compiled into `lfind`. Behaviour identical, `sanity.sh` 56\* the
proof.

## 10. Tests — and where the oracle can actually live

- **`llapi_scan_device_test`** (`lustre/tests/`) — the contract against a
  real target: record versioning, `sp_want` holding back both xattrs *and*
  the size, the pre-filter seeing nothing an xattr paid for, the same object
  digest at 1, 2, 4 and 8 threads, a consumer's stop value coming back,
  internal objects held back by default, bad arguments refused.
- **The oracle: `conf-sanity` test_165, not `sanity`.** The plan was a
  `sanity` test against the mounted MDT. That test would be flaky, and the
  reason is §8.3 of the scanner design: the scan does not read the journal.
  Objects created seconds earlier are in the journal and not yet checkpointed
  to the inode table, so a client-visible FID can legitimately be absent from
  the device — a miss that is the timing's, not the scanner's. `stopall`
  makes it deterministic: the client FID set is gathered first, the
  filesystem is stopped, the scan runs against a quiet device, and misses
  must be zero. `conf-sanity` is where stopping targets is routine.
- **A synthetic image** for the classification ladder — the prototype's
  `tests/mkimage.sh` builds one with `mke2fs` and `debugfs` alone, no root
  and no mount. Used to validate this patch (§13); not yet in tree.

The shared test harness needed one change: `run_tests()` insists its subject
is a directory on a Lustre mount, which a device is not. It now does its
Lustre checks and hands off to `run_test_tbl()`, which is what the device
test calls.

## 11. What is built, and what is left

**Built 2026-08-19**, five commits in `../lustre-lu20603` on top of the
LU-20603/LU-20605 series:

| Commit | What |
|---|---|
| `llapi: scan an ldiskfs target directly` | the call, classification, record fill, worker pool, plugin loading, backend ABI, ldiskfs backend, man page, `llapi_scan_device_test`, conf-sanity test_165 |
| `llapi: split the deciding half out of cb_find_init` | LU-20605's other half: the checks, the glimpse and the printing, behind `struct find_ctx` |
| `lfs: share find's predicate parsing` | the option table, its loop and thirteen argument helpers into `lfs_find_parse.c`, compiled into both `lfs` and `lfind` |
| `llapi: run find's predicates over a device scan` | `llapi_find_device()`: the record presented as an `lmd`, the LMV converted, the size rule |
| `utils: lfind, find over a scan of a target` | `lfind(8)`, its three target spellings, `Documentation/man8/lfind.8`, the test_165 predicate check |

Folded into LU-20603 while it is in review: `sr_projid` on both producers, the
§3.2 `ALL_MASK` fix, and a `sp_size` rule that accepts a caller built against a
*shorter* parameter struct — without which the struct could not grow and
`sp_stats` could not have been added at all.

### What running it found

Four bugs, each caught by an actual run rather than a reading:

1. **A size claimed as authoritative for a striped file** when the demand mask
   had not asked for one, so no layout had been read to know better.
2. **`LLAPI_SCAN_PARENT` set for an all-zero parent FID.**
3. **An OST scan would have returned nothing** — §5.
4. **Every object after a 60-stripe file matched `--stripe-count 60`**,
   including a directory with no layout at all: `fp_lmd` and `fp_lmv_md` are
   one buffer each for the whole scan, and an object without a layout inherited
   the last one's. The namespace producer never sees this because its gather
   overwrites the buffer from the ioctl every time.

And one in code that was already upstream: **`lfs find` exits 0 after a bad
`--comp-flags` or `--mirror-state`**. Those failures leave `ret` at 0 and jump
to the cleanup, so the error is printed and the command reports success. The
refactor had to *preserve* it — hence the `stopped` flag out of
`lfs_find_parse()` — because fixing it changes what the command returns and is
its own patch. Worth filing.

### How far it is verified

| Check | Result |
|---|---|
| `llapi_scan_device_test`, 7 contract cases | pass, against a synthetic MDT image |
| Scanner vs the prototype `lfind-ldiskfs` on that image | same 18 FIDs, same class counts, identical at 1/2/4/8 threads |
| `lfind` predicates on that image | `--type f` 17 + `--type d` 1 = 18; `--projid 1999`, `--name` (including a second linkea name), `--mdt-count 4`, `--stripe-count 60`, `--size +1G` via SOM all correct; `--internal` 27 |
| Moved code, byte-compared | the deciding half and the 987-line parse loop are identical to what they replace, modulo the intended substitutions |
| `lfs find` before and after the refactor | 14 deterministic argument cases identical; the rest differ *from themselves* between two runs of the same binary, because the traversal interleaves its threads' stderr |
| **`sanity` 56\*, conf-sanity test_165** | **never run** — no lab; the workstation has no Lustre |

**Not built, in order:**

1. A real-MDT run: rebuild `tests/lab-scan/` stages 01→04, ~40 min, then
   `sanity` 56\* for the refactor and conf-sanity test_165 for the scanner.
2. Checkpoint and restart, rate limiting, the ZFS backend behind the same call,
   and the Object Stream serialization — each a ticket of its own.
3. `--target`/`--local` have never run against a mounted target, only against
   the no-targets path on this workstation.

## 12. Open questions carried in

From `design-ldiskfs-scanner.md` §15, the ones this series has to answer or
explicitly defer:

| Question | Where it lands here |
|---|---|
| Internal-object exclusion | deferred to **LU-20602**; §5 documents the three that leak |
| Should a resumed scan be flagged? | moot until checkpointing ships |
| `--paranoid` for destructive consumers | `sp_flags`, once a destructive consumer exists to ask for it |
| Orphan reporting | answered: `sr_class` plus `LLAPI_SCAN_F_INTERNAL`, so the consumer chooses |
| Throttling policy | deferred with rate limiting |
| Replica vs primary (LMR) | still open upstream; the record carries `sr_lma_*` so a later flag needs no new field |
