# LFU Changelog Input Scanner — Detailed Design

**Date:** 2026-08-25 · **Status:** design proposal, **v0.2**, no code yet ·
**Parent architecture:** [`architecture.md`](architecture.md) §"Changelog: an
input, not a casualty" · **Plan slot:** [`plan-2.18.md`](plan-2.18.md) gap 2
and 3, **two** Technical tasks under LU-20462 (§11).

Code references are to `../lustre-lu20603` @ `5afbab284e` (upstream master),
and are **[verified]** where the line was read.

**What v0.2 settled**, all of it in §0: the CLI is two flags rather than one,
the record is the truth for what an event said, the command coalesces, an
approximate size is `--lazy` and a real one is a glimpse on the consumer, and
a server-side size filter is refused on soundness rather than on cost. All 83
`lfs find` options were then swept against the changelog (§13.4), which is
what turned the refusals into four stated reasons rather than a list.

---

## 0. The recommendation, in one page

**Build the changelog as a delta source with two faces, not as a third
scanner.** A changelog answers *what happened*; the Object Stream is about
*what is*. Every contradiction §13.3 found came from that seam, so the seam
goes in the interface:

| | `lfs find --since` | `lfs find --changelog` |
|---|---|---|
| answers | **as it is now** | **as it was recorded** |
| the changelog's role | a candidate set; every hit verified | the whole source |
| result | a strict subset of an ordinary `find` | events, coalesced to one line per object |
| sees deletions | no — they cannot be verified | yes |
| a predicate it cannot answer | none; it verifies | refused, or counted undecided |
| a predicate that would mean something else | — | refused, not reinterpreted (`--mdt`) |
| an approximate size | `--lazy`, as today | `--resolve --lazy` |

Both sit on one module, `llapi_scan_changelog()` (§3), which emits the record
`llapi_scan_namespace()` and `llapi_scan_device()` already emit.

**What to build, in order** — §11 has the detail:

1. `llapi_scan_changelog()`, event mode. Small; proves the appended fields.
2. Object mode: the FID hash, aged, keyed on the target FID. Grouping by
   parent is an aggregate Filter Rule, not a second key (§5.2).
3. Resolution through a client mount, gated by the demand mask.
4. `lfs find --since`. Nearly free: candidates from 2, verification from the
   gather `llapi_scan_namespace()` already does.
5. `lfs find --changelog`, with the three refusal rules of §13.1.
6. The Changelog Output Filter — **last**, and smaller than the HLD implies.

**What to refuse, and why:**

- **Tier-3 predicates pushed to the MDS** (§7.2.2). Not because they are
  expensive, but because the MDS does not have the answer: size lives on the
  OSTs, and SOM is exact only for FLR and DoM files. Dropping records against
  a stale-low value loses big files from the answer.
- **Registering a changelog user for the caller** (§4.2). Registering without
  consuming is how an MDT fills up.
- **Persistent state inside the module** (§4.3), except the `--since-cookie`
  of per-MDT indexes, which exists because a bare index means nothing under
  DNE (§13.2).

**The rule that decides every flag** (§13.4, §13.5):

> A predicate is answered from what the source actually has, or refused. It is
> never approximated, and never reinterpreted.

Four things make a predicate refusable under `--changelog`: it needs object
state and `--resolve` was not given; it describes a walk; it needs the mounted
filesystem's target list; or **the record carries something that is not what
the option means** — which is why `-name` is answered from the event and
`--mdt` is refused outright.

The same rule is why a flag can differ between `lfs find` and `lfind` and that
is not a defect: `-name` already does, in shipped code. §13.5 has the
provenance table.

**What is still open:** two questions, both in §12, and both now narrow enough
to answer in a sentence.

---

## 1. Purpose and scope

Produce an LFU Object Stream from a **Lustre Changelog**, so that a consumer
written against `llapi_scan_namespace()` or `llapi_scan_device()` can be fed
by *what changed* instead of *what exists*, without being rewritten.

This is the third of the HLD's three initial Input Scanners, and the only one
that is **not** a scan. That difference runs through the whole design and §9
is where it is stated plainly.

### In scope

- Reading one MDT's changelog through the existing client-side character
  device, in catch-up and follow modes
- Turning changelog events into Object Stream records, with the same record,
  demand mask and pre-filter the other scanners take
- Coalescing an event stream into one record per object, for consumers that
  want objects rather than events
- Resolving the attributes the changelog does not carry, on demand and at a
  price the caller asks for
- Checkpoint and restart on the changelog index; the registration and
  clearing contract that makes that safe
- The **Changelog Output Filter**: pushing predicates to the server so records
  are dropped before they cross the wire (§7) — which §7.2.1 shrinks to the
  type-mask drop plus the predicates the record already carries, and §7.2.2
  refuses to extend to size
- The two `lfs find` spellings this reaches a user through, and the rules that
  keep them from meaning each other (§13.1)

### Out of scope

- Answering "what is in the filesystem" — see §9. A changelog answers "what
  changed since X" and nothing else.
- Cross-MDT merge, which is the Merge/Split Filter Rule (`plan-2.18.md` gap 4),
  shared with the device scanner. §8.3 states what merged order can mean.
- Changing what the MDS records. The recorded set is an administrator's
  setting (`mdd.*.changelog_mask`) and this module reads what is there.

---

## 2. What a changelog record actually carries

The design is shaped by this table more than by anything else.

`struct changelog_rec` (`lustre_user.h:2100`) **[verified]**:

| Field | What it is |
|---|---|
| `cr_type` | the event: `CL_CREATE`, `CL_UNLINK`, `CL_SETATTR`, … (`lustre_user.h:1901`) |
| `cr_index` | the record number on this MDT — the cursor for restart |
| `cr_prev` | the previous index **for this target FID**, i.e. a back-link through one object's history |
| `cr_time` | when the event happened |
| `cr_tfid` | the target FID (or `cr_markerflags` for `CL_MARK`) |
| `cr_pfid` | the parent FID |
| `cr_namelen` + name | the name within the parent |

Optional extensions, each present only when asked for at open time and
recorded by the server (`lustre_user.h:2114-2154`) **[verified]**:

| Extension | Gate | Carries |
|---|---|---|
| `changelog_ext_rename` | `CLF_RENAME` | source FID and source parent FID |
| `changelog_ext_jobid` | `CLF_JOBID` | the job id |
| `changelog_ext_uidgid` | `CLFE_UIDGID` | **uid and gid** |
| `changelog_ext_nid` | `CLFE_NID` | the client NID |
| `changelog_ext_openmode` | `CLFE_OPEN` | open flags |
| `changelog_ext_xattr` | `CLFE_XATTR` | the xattr *name* |

**What is not there, at any setting:** size, blocks, mode, nlink, the object's
own atime/mtime/ctime/btime, projid, layout, directory stripe, HSM state,
linkea. A changelog record describes an *event*, not the object's state after
it.

So the record this module can fill for free is exactly:

```
sr_fid  sr_parent_fid  sr_name  sr_uid  sr_gid   + the event itself
```

Everything else in `struct llapi_scan_rec` is either absent — with its
`sr_valid` bit clear, which is what that mask is for — or costs a lookup
(§6).

### 2.1 Two settings that decide what exists at all

- **`CHANGELOG_DEFMASK`** excludes `CL_ATIME`, `CL_OPEN`, `CL_GETXATTR` and
  `CL_DN_OPEN` (`lustre_idl.h:3062`) **[verified]**, *"since it can really be
  time consuming"*. **A default filesystem cannot answer "recently accessed"
  from its changelog.** That matters directly to the HLD's oldest-atime index
  idea, and it is not something this module can fix — enabling `CL_ATIME` is
  an operator's decision with a throughput cost.
- **`CL_CLOSE`** is recorded *"may be written to log only with mtime change"*
  (`lustre_user.h:1914`) **[verified]**, so "the file was written" arrives as
  a close only when the write actually changed something.

### 2.2 The one attribute an event implies

A creation's event type is chosen from the mode
(`lustre/mdd/mdd_dir.c:2812-2814`) **[verified]**:

```
S_ISDIR  -> CL_MKDIR      S_ISREG -> CL_CREATE
S_ISLNK  -> CL_SOFTLINK   else    -> CL_MKNOD
```

So `CL_CREATE` means a regular file, `CL_MKDIR` and `CL_RMDIR` a directory,
`CL_SOFTLINK` a symlink — and `CL_MKNOD` narrows only to "one of block,
character, fifo or socket", which is not an `S_IFMT`.

This is the changelog's version of what `LLAPI_SCAN_TYPE` already means for a
namespace walk: *"only the S_IFMT of sr_mode, from the dirent; no I/O behind
it"* (`lustreapi.h:576-577`) **[verified]**. The module sets `LLAPI_SCAN_TYPE`
from the event where the event decides it, and leaves it clear otherwise —
so `-type f` is answerable for free on a creation and needs a lookup on a
`CL_SETATTR`. Nothing else in the record implies an attribute this way.

---

## 3. Interface contract

Same shape as the other two Input Scanners: a size-guarded parameter struct, a
demand mask, a pre-filter, one callback per object, and the same record.

### 3.1 Request

```c
struct llapi_scan_changelog_param {
	__u32		 scp_size;	/* sizeof(*scp), required */
	__u64		 scp_want;	/* LLAPI_SCAN_* the consumer reads */
	llapi_scan_cb_t	 scp_filter;	/* before any lookup, or NULL */
	__u64		 scp_flags;	/* LLAPI_SCAN_CL_F_* */
	const char	*scp_mdtname;	/* "testfs-MDT0000" */
	const char	*scp_user;	/* "cl1", or NULL to register one */
	const char	*scp_mnt;	/* client mount, for §6 resolution */
	__u64		 scp_startrec;	/* resume point, 0 = oldest kept */
	__u64		 scp_endrec;	/* 0 = to the end of what exists */
	__u64		 scp_type_mask;	/* BIT(CL_*) — pushed, see §7 */
	__u32		 scp_min_age;	/* seconds; hold an object this long
					 * before emitting it, so a burst of
					 * events coalesces into one record
					 */
	__u32		 scp_max_cached; /* objects held while coalescing */
	struct llapi_scan_stats *scp_stats;
};

int llapi_scan_changelog(const struct llapi_scan_changelog_param *scp,
			 llapi_scan_cb_t cb, void *data);
```

Flags:

| Flag | Meaning |
|---|---|
| `LLAPI_SCAN_CL_F_FOLLOW` | do not stop at the end; wait for new records (`CHANGELOG_FLAG_FOLLOW`) |
| `LLAPI_SCAN_CL_F_COALESCE` | object mode (§5.2) rather than event mode (§5.1) |
| `LLAPI_SCAN_CL_F_RESOLVE` | fill what the changelog does not carry, through `scp_mnt` (§6) |
| `LLAPI_SCAN_CL_F_CLEAR` | clear consumed records as they are delivered (§4.2) — **destructive**, off by default |

### 3.2 What the record gains

Five appended fields and three bits, which is what `sr_size`/`sr_valid` exist
for. Highest bit in use today is `LLAPI_SCAN_GEN 0x02000000`
(`lustreapi.h:603`) **[verified]**, so:

```c
#define LLAPI_SCAN_EVENT	0x04000000ULL	/* sr_event_* */
#define LLAPI_SCAN_EVENT_SRC	0x08000000ULL	/* the rename source */
#define LLAPI_SCAN_JOBID	0x10000000ULL	/* sr_jobid */
```

| Field | From |
|---|---|
| `sr_event_type` | `cr_type` |
| `sr_event_time` | `cr_time` — *when it happened*, not an object time |
| `sr_event_index` | `cr_index`, so a consumer can checkpoint |
| `sr_event_flags` | the per-type bits below `CLF_FLAGMASK`: `CLF_UNLINK_LAST`, the HSM event and error, `CLF_RENAME_LAST` |
| `sr_src_fid`, `sr_src_parent_fid`, `sr_src_name` | the rename extension |
| `sr_jobid` | the jobid extension |

`sr_event_time` deliberately does **not** land in `sr_mtime`. An event time
and a modification time are different facts, and a consumer filtering on
`--mtime` must not be handed one when it asked for the other.

---

## 4. Operating model

### 4.1 Where it runs, and what it needs

**On a client.** The changelog is read through `/dev/changelog-<mdtname>`
(`liblustreapi_chlg.c:32-44`) **[verified]**, a character device the *client's*
`mdc` module creates per MDT connection. So unlike the device scanner, this
module needs no server access and no privileged block device — only a mounted
client and permission on that device node.

**Registration is the server's, though.** `OBD_IOC_CHANGELOG_REG` is handled
in `mdd_device.c:2352` and `mdt_handler.c:8220` **[verified]** — i.e.
`lctl --device <mdtname> changelog_register [--mask M] [--user NAME]` runs on
the **MDS**. A consumer therefore needs an already-registered user id, which
is why `scp_user` is a parameter and not something the module can conjure.

### 4.2 The clearing contract, which is the dangerous part

A registered changelog user is a promise to consume. Two failure modes, both
operational rather than theoretical:

- **Clear too eagerly and you destroy another consumer's records.**
  `llapi_changelog_clear(mdtname, id, endrec)` (`liblustreapi_chlg.c`)
  **[verified]** purges everything up to `endrec` *for that user id*. A user
  id shared with Robinhood or `lustre_rsync` loses whatever we clear past.
- **Never clear and the MDT fills.** Unconsumed records accumulate in the
  changelog llog for as long as the user stays registered.

The design's answer:

1. `LLAPI_SCAN_CL_F_CLEAR` is **off by default**. Without it the module reads
   and never purges; the caller checkpoints `sr_event_index` and clears on its
   own schedule.
2. With it, the module clears only up to the index of a record it has
   **delivered and the consumer accepted**, never ahead of the callback.
3. The man page will state, in the words this section uses, that registering a
   user without a consumer is how an MDT runs out of space — and that
   deregistering is the cure.

### 4.3 Checkpoint and restart

`cr_index` is the cursor: `llapi_changelog_start()` `lseek()`s to `startrec`
(`liblustreapi_chlg.c`) **[verified]**, so a restart is "the last index I
accepted, plus one". This is cheaper and stronger than the device scanner's
restart, which resumes at an inode number and re-reads a fuzzy window: a
changelog restart loses nothing and repeats nothing, provided the records are
still there.

---

## 5. Two modes, because there are two consumers

### 5.1 Event mode — one record per event

The default. Records arrive in changelog order, one callback per event,
`sr_event_*` populated, no state held. This is what the HLD means by
*monitoring ongoing modifications*: audit trails, replication feeds, HSM
policy triggers.

### 5.2 Object mode — one record per object

`LLAPI_SCAN_CL_F_COALESCE`. Events are accumulated in a FID-keyed hash and
emitted once per object, carrying the union of what its events said plus the
latest event's index and time.

**The key is always the target FID.** An earlier draft made it a parameter,
so that a caller could coalesce on `cr_pfid` instead and get one record per
directory that had activity — which is what the HLD's Aggregates section asks
for when it observes that *"it is sufficient to track the parent directory FID
once for any number of files created, written, deleted in that directory"*.

That belongs somewhere else. By this project's own taxonomy a **Filter Rule**
is what *"consume[s] one or more Object Streams, produce[s] another; matching,
merging, aggregation"* (`architecture.md:25`), and grouping records by a field
is aggregation. Making it a scanner mode would mean one module emitting
records that describe two different kinds of thing, which is the defect
§13.4 finding 3 caught in the CLI and the same defect one layer down.

So: **grouping by parent FID is an aggregate Filter Rule — `group by
sr_parent_fid` — and it applies to any Object Stream**, not only this one.
Over a device scan it answers "which directories contain objects matching X",
which is the same question a different way.

**The efficiency argument survives, as pushdown.** Grouping downstream costs
the full stream: the scanner holds a hash of objects and delivers one record
each, and on a filesystem with millions of files in few directories that is
two orders of magnitude more records than the consumer wants. So the rule is
*expressed* once as a Filter Rule and *applied* by the scanner inline when it
can — the same pushdown this design already does for predicates (§7.2) and the
device scanner already does for filters. The scanner's hash then holds
directories rather than objects, and the volume is paid once.

Until that Filter Rule exists, a consumer that wants this does it in a few
lines: every emitted record carries `sr_parent_fid`, so the grouping needs no
extra I/O — only the volume the pushdown would have saved.

An object leaves the cache when:

- it has been quiet for `scp_min_age` seconds, or
- the cache reaches `scp_max_cached` and the oldest is evicted, or
- the stream ends (catch-up mode) or the consumer stops.

This is exactly the shape `llsom_sync(8)` already uses — a FID hash, a
`REC_MIN_AGE` of 600 s, batched flushes (`llsom_sync.c:38`, `:96-130`, `:210`)
**[verified]** — and reusing its shape is deliberate: it is the one in-tree
consumer that has had to solve this.

**Unlink is the case that decides the semantics.** Within one window an object
can be created and removed. Object mode therefore reports the *net* state:

| Events seen for one FID | Emitted |
|---|---|
| create … modify … | one record, `sr_event_type = CL_CREATE`, latest index |
| create … unlink | nothing, unless the consumer asked for unlinks |
| modify … unlink | one record with `CL_UNLINK`, attributes unresolvable (§6) |
| rename | one record, with `LLAPI_SCAN_EVENT_SRC` giving where it came from |

---

## 6. Attributes the changelog does not carry

Three honest options, and the demand mask picks between them per call:

1. **`scp_want` asks only for what §2 lists as free.** No lookup, no mount
   needed, and the stream runs at changelog speed.
2. **`scp_want` asks for more, without `LLAPI_SCAN_CL_F_RESOLVE`.** The fields
   are delivered absent — `sr_valid` clear — and a pushed-down filter that
   needs them counts the object as *undecided* and says so at the end, exactly
   as `llapi_find_device()` does for a field an MDT cannot answer.
3. **`scp_want` asks for more, with `LLAPI_SCAN_CL_F_RESOLVE`.** The module
   opens the object by FID through `scp_mnt` and gathers, which is
   `llapi_open_by_fid()` plus a `statx` — the same one-open-per-object cost
   `llsom_sync` pays (`llsom_sync.c:160`) **[verified]**.

Resolution has two failure modes worth naming rather than hiding:

- **The object is gone.** An unlinked FID cannot be opened. The record is
  delivered with the event and no attributes; this is normal, not an error.
- **The object changed after the event.** Resolution reports the object *now*,
  not as it was when the event was recorded. For "what changed recently" that
  is usually what a consumer wants, and for an audit trail it is not; the man
  page must say which it is giving.

Coalescing (§5.2) is what makes option 3 affordable: a file written a hundred
times in a minute is one lookup, not a hundred.

---

## 7. Filter pushdown, and the Changelog Output Filter

### 7.1 What exists today

- The **server records** whatever `mdd.*.changelog_mask` says, for all users.
- A **registered user** carries a mask; `mdc_changelog_get_user_info()` fetches
  it from the MDT with `MDS_GET_INFO` (`mdc_changelog.c:722`) **[verified]**.
- `llapi_changelog_start_user()` sends `OBD_IOC_CHANGELOG_FILTER` with a
  `struct changelog_filter`, and the effective mask becomes the intersection
  of the request and the user's registered mask (`mdc_changelog.c:810-815`)
  **[verified]**.
- That mask drops records **on the client**, in
  `chlg_read_cat_process_cb()` (`mdc_changelog.c:184`, the test at `:222`)
  **[verified]**:
  `!(crs->crs_user_mask & BIT(rec->cr.cr_type))` → the record is skipped.

So filtering today is **by type only, and after the records have crossed the
wire**. That is the gap the HLD names: *"there is currently no mechanism to
filter Changelog events based on specific attributes"*.

### 7.2 What the Output Filter should be, in tiers

The same cost tiering the device scanner uses, applied to a different source:

| Tier | Predicate | Where it can run | Cost |
|---|---|---|---|
| 0 | record type | already pushed; move the drop to the **server** so it saves transfer too | free |
| 1 | uid, gid, NID, jobid, open flags, xattr name | **server-side, from the record itself** — these are in the extensions of §2 | a mask test per record |
| 2 | name (`--name`), parent FID, rename source | server-side, from the record | a `fnmatch` per record |
| 3 | size, blocks, mode, layout, HSM state, project id | **cannot be pushed** — see §7.2.2, which is a soundness argument and not only a cost one | an open per record on the MDS, and a wrong answer |

**The recommendation is that tiers 0–2 are the Changelog Output Filter and
tier 3 is refused there.** "Files over 1 TB" — the HLD's own example — is a
tier-3 predicate, and pushing it to the MDS buys a transfer saving at the cost
of MDS work on every recorded event. The honest place for it is after
resolution (§6), on the consumer, where the object is already open.

That refusal should be explicit in the API rather than silent, exactly as
`find_device_supported()` refuses `--ost`/`--mdt` on a target scan today.

### 7.2.1 The filter is smaller than the HLD implies

The HLD gives three examples of what an attribute filter would be for:
*"objects created by UID 1000"*, *"files over 1TB in size"*, and consumers
interested in *"whether a redundant file layout is stale"*. Checked against
the tree, they land in three different places:

| HLD example | Where it actually belongs |
|---|---|
| created by UID 1000 | **tier 1** — `CLFE_UIDGID` puts uid in the record already |
| a redundant layout is stale | **tier 0, and it already works** — `CL_FLRW` is recorded when a mirrored file is first written, with the comment *"record a changelog for data mover to consume"* (`mdd/mdd_object.c:3263`) **[verified]**, and `CL_RESYNC` when it is resynced (`:3470`). Subscribing to those two types is the existing per-user mask; no new filter is needed |
| over 1TB in size | **tier 3** — not in the record at any setting, so the MDS would have to open the object per event |

So two of the three motivating examples need no attribute filter at all, and
the third is the one that costs the MDS. **What remains for the Output Filter
is: move the existing type mask's drop from the client to the server, and add
the in-record predicates of tiers 1 and 2.** That is a much smaller module
than the section implies, and a much easier one to defend on the metadata
server's hot path.

### 7.2.2 A server-side size filter cannot answer for size

The question "is a server-side filter necessary if a user wants the real file
size" has a sharper answer than the cost one: **the MDS does not have the real
size, so the filter is neither necessary nor sufficient.**

A file's size lives on its OSTs. What an MDT holds is size-on-MDT, and its own
header says what that is worth (`lustre_user.h:542-555`) **[verified]**:

| SOM state | What it promises |
|---|---|
| `SOM_FL_UNKNOWN` | *"Unknow or no SoM data, must get size from OSTs"* |
| `SOM_FL_STRICT` | *"Known strictly correct, FLR or DoM file (SoM guaranteed)"* |
| `SOM_FL_STALE` | *"was right at some point in the past, but it is known (or likely) to be incorrect now (e.g. opened for write)"* |
| `SOM_FL_LAZY` | *"Approximate, may never have been strictly correct"* |

So an MDS-side `-size +1T` would be evaluated against a value that is exact
only for FLR and DoM files and approximate or stale for everything else. The
authoritative answer needs a glimpse to the OSTs, and a glimpse is a client
operation: asking the metadata server to issue OST RPCs per recorded event is
not a filter, it is a second workload.

**That makes tier-3 dropping unsound, not merely expensive.** A file whose
SOM reads 4 GB while it is open for write may be 2 TB on disk; dropping its
record loses it from the answer, and a search that silently misses is the
failure mode this project keeps refusing everywhere else — skipped objects
counted on the device scanner, a stale `--since` anchor refused, `--ost` and
`--mdt` refused on a target scan.

Two consequences, and they are the recommendation:

1. **A real size belongs on the consumer, after resolution.** That is
   `statx()` through the mount, which is what `lfs find -size` does today, and
   what `--resolve` gives a changelog consumer.

   **And the approximate size has a flag already: `--lazy`.** It is documented
   as *"Use file size and blocks from MDT, if available, to avoid extra
   RPCs"*, and in the code it is the gate that lets `OBD_MD_FLLAZYSIZE`
   satisfy `-size` where `OBD_MD_FLSIZE` would otherwise be needed
   (`liblustreapi_pfind.c:2887-2893`) **[verified]**. So the two questions a
   user might be asking already have two spellings, and neither needs a
   server-side filter:

   | Command | Size it uses | Cost |
   |---|---|---|
   | `--resolve -size +1T` | the real one, glimpsed from the OSTs | an open and a glimpse per candidate |
   | `--resolve --lazy -size +1T` | the MDT's SOM value | an open per candidate, no OST RPC |

   With `--lazy`, an object whose SOM is `UNKNOWN` — never closed since SOM
   data began — is still not answerable, and counts undecided rather than
   matching as zero. That is the same rule as everywhere else in this design.

   Note the contrast with `llapi_find_device()`, which *forces* `fp_lazy = 1`
   (`liblustreapi_pfind.c:3537-3538`) **[verified]** because a target scan has
   no mount to glimpse through. A changelog consumer has one, so here `--lazy`
   is the caller's choice rather than a constraint.
2. **If the goal is volume** — the HLD's stated one, *"reduce the number of
   unnecessary Changelog records"* — then a size pre-filter is admissible only
   as a **conservative** one: drop a record only when the value is
   `SOM_FL_STRICT` and definitively fails the predicate, and pass everything
   else through for exact evaluation downstream. Sound, and worth little,
   because STRICT is the minority case.

The same distinction is already in our shipped code: 68156 sets
`LLAPI_SCAN_SIZE` for `SOM_FL_STRICT` and the `LAZY_*` bits otherwise,
precisely so an approximate size is never reported as an exact one.

### 7.3 Where the server-side drop would live

Records reach the client through the llog read RPC that backs
`chlg_read()`. A server-side filter means evaluating the mask in the MDT's
llog handler for changelog reads, before packing the reply — with the same
`struct changelog_filter` extended by an attribute predicate list. That is a
protocol change and therefore a separate, later change from the Input Scanner
itself; §11 sequences them apart.

---

## 8. Ordering, DNE, and what "since" means

### 8.1 Order within one MDT

`cr_index` is monotonic per MDT, so within one changelog the order is exact
and total. This is the one place where LFU gets a strictly ordered stream.

### 8.2 `cr_prev` is a back-link, not a history

`cr_prev` gives the previous index for the same target FID
(`lustre_user.h:2105`) **[verified]**, which is useful for walking one
object's history backwards — but only as far as records still exist. After a
clear it points into purged space. The module will expose it as
`sr_event_prev` and document that limit rather than build on it.

### 8.3 DNE: N changelogs, no global order

One changelog per MDT. A merged stream can be ordered by `cr_time`, which is
a wall clock on each MDS and therefore approximate across servers; it cannot
be ordered by index, which is per-MDT. So:

- **Per-MDT order:** exact.
- **Merged order:** approximate, by `cr_time`, and the man page will say so.
- A rename that moves an object between MDTs appears in both changelogs.

### 8.4 The anchor problem

"Since index N" is meaningful only if the consumer knows what the namespace
looked like at N. The pipeline answer, already stated in
`option-comparison.md`, is that a full scan establishes the baseline and the
changelog maintains it. A changelog scanner with no anchor can answer *what
changed*, and can never answer *what matches*.

---

## 9. What this module cannot do

Stated once, plainly, because every other section leans on it:

1. **It is not a scan.** It enumerates events, not objects. An object that has
   not changed does not appear, however well it matches.
2. **Its window is finite and destructible.** Records exist between the oldest
   unpurged index and now. Clearing is irreversible; not clearing fills the
   MDT.
3. **`CL_ATIME` is off by default**, so "not accessed in a year" is not a
   changelog question on a default filesystem (§2.1).
4. **A directory rename moves a subtree without emitting a record per child.**
   A consumer maintaining paths must re-resolve the subtree itself; the
   changelog will not tell it which children moved.
5. **Attributes are absent unless resolved**, and resolution reports the
   object now, not at the event (§6).

---

## 10. Prior art, in tree

| Consumer | What it does | What we take |
|---|---|---|
| `llsom_sync.c` **[verified]** | keeps SOM up to date from `CL_CLOSE`/`CL_TRUNC`/`CL_SETATTR` | the FID hash, `REC_MIN_AGE`, batching, clear-after-consume |
| `lustre_rsync.c` **[verified]** | replicates a namespace from the changelog | rename and unlink handling; the status-file checkpoint pattern |
| `lfs changelog` **[verified]** | prints records | the reader loop and `CHANGELOG_FLAG_*` usage |

None of them produces an Object Stream, and none of them can be filtered by
attribute. That is the whole of what this module adds over them.

---

## 11. Sequencing

| # | Step | Size | Notes |
|---|---|---|---|
| 1 | `llapi_scan_changelog()`, event mode, no resolution | small | delivers records from a real changelog into the existing consumer contract, and proves the appended fields of §3.2 |
| 2 | Object mode — the FID hash, ageing, eviction | small–medium | §5.2; `llsom_sync` has the shape already |
| 3 | Resolution through a client mount, gated by the demand mask | medium | §6, and the per-object cost centre |
| 4 | `lfs find --since` | **nearly free** | candidates from 2, verification from the gather `llapi_scan_namespace()` already does |
| 5 | `lfs find --changelog` and the three refusal rules | small | §13.1; mostly argument validation |
| 6 | Changelog Output Filter: the type-mask drop moved server-side, plus tier-1 and tier-2 predicates | separate ticket | a wire-protocol change (§7.3), and worth doing only after 1–5 show which predicates are pushed in practice |

Steps 1–5 are the "Changelog Input Scanner" task; step 6 is the "Changelog
Output Filter" task. `plan-2.18.md` files them as one — this design argues
they are two, because 6 changes the protocol and 1–5 do not, and because
§7.2.1 shrinks 6 to something much smaller than the HLD's paragraph implies.

Step 4 is the argument for this ordering. It is the piece a user sees, and it
costs almost nothing once 2 and 3 exist, because the verification half is code
that shipped this month.

---

## 12. Open questions

**Two questions need someone else to answer.** Both are narrow enough to
settle in a sentence, which is the point of having worked the rest out first.

| Question | Why it matters | What to ask |
|---|---|---|
| **Was "files over 1TB" meant as an MDS-side filter?** | §7.2.2 shows the MDS does not have the size to filter on: SOM is exact only for FLR and DoM files, and dropping against a stale-low value loses big files. Meanwhile the consumer can already choose real (`-size`) or approximate (`--lazy`) | Did you mean a **conservative** prune over `SOM_FL_STRICT` only, or was size an illustration and the check belongs on the consumer? This decides the size of step 6 |
| **`--since <time>` under DNE, and who owns the cookie** | `cr_time` is a wall clock on each MDS, so a time is comparable across MDTs only as far as the clocks are (§8.3). The `--since-cookie` of per-MDT indexes is exact, and is state | Approximate by clock, or refuse beyond a skew margin? And is the cookie ours, or does it belong with whatever the Merge/Split Filter Rule uses for multi-target state? |

**Settled in v0.2, and argued in §13:** the CLI is `--since` plus
`--changelog` (§13.1); the record is the truth for what an event said and
resolution only fills what is missing (§13.1); the command always coalesces
(§13.1); a bare index is refused under DNE (§13.2); `--mdt` is refused under
`--changelog` (§13.4); a flag may mean different things from different sources
(§13.5). Elsewhere: an approximate size is `--lazy` (§7.2.2) and registration
stays the caller's (§4.2).

**Smaller things to settle with a lab rather than a meeting:** the default
`scp_min_age` — start at `llsom_sync`'s 600 s and measure; and whether the
pre-filter earns its place in event mode, where there is no I/O to save unless
resolution is on.

## 13. The command line

How this reaches a user, and the rules that keep two sources from being
mistaken for each other. §13.1 settles the shape, §13.2 the anchor, §13.3 and
§13.4 test the rules against every invocation and every option, and §13.5
states what a flag is allowed to mean when the source changes.

### 13.1 Source replacement, or accelerator

The first draft of this design proposed `lfs find --changelog MDT`, meaning
*take the source from the changelog instead of a walk*. Working through what
the path argument would then mean says that is the wrong default for
`lfs find`, and the question is worth stating properly because it decides what
the command promises.

`lfs find` requires at least one path and loops over the paths it is given
(`lustre/utils/lfs.c`, `pathstart == -1` is *"no filename|pathname"*)
**[verified]**. Under source replacement that argument stops meaning *search
here* and starts meaning *the mount to resolve through*, so

```
lfs find /mnt/lustre/project42 --changelog testfs-MDT0000 -uid 1000
```

answers for the whole MDT, not the subtree, unless every candidate's pathname
is resolved and prefix-matched at one ioctl each. Three further shifts, all
silent: a predicate the changelog cannot answer becomes undecided rather than
false; one `--changelog MDT` covers one MDT, so a DNE answer is partial; and
the question changes from *what matches* to *what has an event since N and
matches*.

**The alternative is to use the changelog as a candidate set.**

```
lfs find /mnt/lustre/project42 --since <index|time> -uid 1000 -size +1G
```

The changelog supplies FIDs with events since the anchor; each is then
verified through the ordinary path — `statx`, layout, the rest — so every
predicate keeps the meaning it has today, the subtree restriction is
enforceable against the resolved pathname, and the output is pathnames. The
result is a strict subset of what a full `lfs find` would return: narrowed,
never wrong. What is given up is exactly what the flag names — an object that
matches but has not changed since the anchor does not appear.

**Both, under two names.** `--since` is the accelerator above. `--changelog`
is source replacement: it scans the changelog and nothing else.

They are not redundant, and the case that proves it is the unlinked object.
`--since` verifies each candidate through the mount, so an object that has
been removed cannot be verified and drops out of the answer. A consumer
asking *what happened* — deletions, renames, events on objects that no longer
exist — cannot get that from the accelerator at all. That is the event view,
and it needs its own flag rather than a subtly different `--since`.

```
lfs find /mnt/lustre --changelog testfs-MDT0000 --since 4200 -uid 1000
lfs find /mnt/lustre --changelog all --since 4200 -type f   # see rule 1
```

**Three rules keep the two apart.** Without them `--changelog` is the silent
meaning-shift §13.1 opened with; with them the difference is enforced at the
command line rather than explained in a man page.

1. **A predicate the changelog cannot answer is refused, not approximated.**
   `-size`, `-blocks`, `-layout`, `-projid`, `--hsm-state` and the rest of
   tier 3 exit with an error naming the predicate, unless `--resolve` is
   given. This is the model `find_device_supported()` already ships for a
   target scan. `-type` is the one predicate that straddles the line: §2.2
   answers it for a creation and not for anything else, so without
   `--resolve` it matches the creations and counts the rest undecided rather
   than refusing outright.

   **Resolution fills; it never removes and never overrides.** An object that
   no longer exists is still delivered, with the fields the stream gave it and
   the rest absent; a predicate that cannot then be evaluated counts the
   object undecided and says so at the end, exactly as `llapi_find_device()`
   does. Adding `--resolve` must not make the answer smaller.
   `-type` is the one predicate that straddles the line: §2.2 answers it for
   a creation and not for anything else, so without `--resolve` it matches
   the creations and counts the rest undecided rather than refusing outright.
   The second example below is that case.
2. **The path argument means the mount, and says so.** Under `--changelog` the
   path is what FIDs are resolved against, not a subtree restriction — a
   changelog is per-MDT and knows nothing about where in the namespace an
   object sits. A path below the mount point is refused unless `--resolve` is
   given, because only then can a pathname be produced and prefix-matched.
3. **Output is a pathname where one exists and a FID where one does not.**
   An unlinked object has no pathname; printing the FID is the whole point of
   asking. `lfind(8)` already prints FIDs for the same reason.

**The one-line difference between the two flags:** `--since` answers *as it
is now* — every candidate is verified against the live object — and
`--changelog` answers *as it was recorded*. That is why `-name` under
`--changelog` matches the name in the event and not the object's current
name, and why `-uid` matches the uid the event recorded even when `--resolve`
is given. Resolution adds fields the stream lacks; it does not restate the
ones it has.

**The CLI always coalesces.** `find` prints a path once, and an event stream
has many events per object, so `lfs find --changelog` runs the module in
object mode (§5.2) and emits one record per object. The per-event view is
`llapi_scan_changelog()`'s and `lfs changelog`'s, not `lfs find`'s.

`--changelog` takes an MDT name or `all`; the argument is required rather than
optional, because `getopt_long()` accepts an optional argument only in the
`--changelog=VALUE` form and a required one accepts both spellings, as
`lfind`'s `--device` already does.

The two flags compose: `--changelog` picks the source, `--since` picks where
in it to start. On its own, `--since` starts the accelerator at that index;
on its own, `--changelog` reads from the oldest surviving record.

The cost of the accelerator is one verification per candidate, which is the
same per-object price as §6 resolution — so the two share an implementation:
the candidate set is `llapi_scan_changelog()` in object mode, and the
verification is the gather `llapi_scan_namespace()` already does.

### 13.2 What `--since` takes, and why a bare index is not enough

`lfs find /mnt/lustre --since 4200 -type f` reads the changelogs of the
filesystem holding that path from index 4200, coalesces to candidate FIDs,
resolves and gathers each one through the mount, and prints the pathnames of
those that are regular files. The answer is

> objects with an event at or after 4200 ∩ regular files ∩ still existing

and it excludes, by construction, a matching file that has not changed since
4200 and anything that has been deleted.

**`cr_index` is per-MDT**, so on a DNE filesystem 4200 names a different
instant on each MDT and a bare index across all of them means nothing. That is
the common case for `--since`, which reads every MDT by default. Prior art
agrees: `lustre_rsync` stores one `ls_last_recno` beside one `ls_mdt_device`
(`lustre/utils/lustre_rsync.h:23-33`) **[verified]** — an index is only
meaningful paired with the MDT it came from.

So `--since` takes one of three things:

| Spelling | Meaning | When |
|---|---|---|
| `--since <index>` | that index | **only** with an explicit single `--changelog MDT`, or on a single-MDT filesystem; refused otherwise |
| `--since <time>` | the first record at or after it, per MDT | the human spelling, and the only one that means the same thing on every MDT — subject to §8.3's clock caveat |
| `--since-cookie <file>` | per-MDT indexes written by a previous run | the machine spelling: exact on every MDT, and what a repeated job should use. The run rewrites it at the end |

A cookie is the honest form of "where I got to" under DNE, and it is also
where the stale-anchor check belongs: if an MDT's recorded index is older than
its oldest surviving record, the run refuses rather than quietly returning a
short answer.

### 13.3 Worked examples, and what they exposed

Fourteen invocations, run against the rules above on paper. The first block
behaves; the second block is where the rules had to change.

| Command | What it does |
|---|---|
| `lfs find /mnt/lustre --since 2h -type f` | candidates from every MDT's changelog since that time, each verified; prints pathnames of regular files |
| `lfs find /mnt/lustre/proj --since-cookie ck -uid 1000` | same, restricted to the subtree by prefix-matching the resolved pathname, resuming from the cookie's per-MDT indexes |
| `lfs find /mnt/lustre --changelog testfs-MDT0000 --since 4200` | every object with an event at or after 4200 on that MDT, one line each |
| `lfs find /mnt/lustre --changelog all -type f` | matches creations (§2.2); every other event counts undecided |
| `lfs find /mnt/lustre --changelog all --mdt 1` | **refused** — two readings, and the source selector already spells one of them (§13.4) |
| `lfs find /mnt/lustre --changelog all --skip 90` | sampling applies to matches, as it does today |
| `lfs find /mnt/lustre --changelog all -size +1G --resolve` | size comes from the lookup, glimpsed from the OSTs; objects since deleted are undecided, not dropped |
| `lfs find /mnt/lustre --changelog all -size +1G --resolve --lazy` | the same, from the MDT's SOM value and no OST RPC; `UNKNOWN` SOM counts undecided |

**The seven that changed something:**

| # | Command | The problem | The rule it forced |
|---|---|---|---|
| 1 | `--changelog all -uid 1000` | a file written 50 times would print 50 times, and `find` prints a path once | the CLI always coalesces; the event view is the API's (§13.1) |
| 2 | `--changelog all -size +1G --resolve` | rule 1 said deleted objects are "counted and reported", so adding `--resolve` **shrank** the answer | resolution fills, never removes; undecided is the answer for what it could not fill |
| 3 | `--changelog all -name '*.log'` | the record's name is the name **at the event**; after a rename, an old record carries the old name, and `find` means the current name | `--changelog` answers as-recorded, `--since` as-now — stated as the difference between the flags |
| 4 | `--changelog all -mtime -1` | the record has an event time, not an mtime, and the user means "changed in the last day" | refused, with a message naming `--since 1d` as the way to say it |
| 5 | `--changelog all --maxdepth 2` | a target scan refuses `--maxdepth` because there is no walk — but under `--since` the resolved pathname makes depth answerable | refused under `--changelog`; honoured under `--since` |
| 5b | `--changelog all --mdt 1` | called free at first, and it is not: the changelog an event arrived in is not always the object's MDT, so the flag has two readings | refused outright under `--changelog`; available under `--since` (§13.4) |
| 6 | `lfs find /mnt/a /mnt/b --changelog all` | under `--changelog` the path is the mount, so two paths are two filesystems | one path per invocation with `--changelog`; `--since` may take several, as `lfs find` does today |
| 7 | `--changelog all -printf '%p %s\n'` | every `-printf` conversion reads object state — path, size, mode, nlink, uid (`liblustreapi_pfind.c:2013-2030`) **[verified]** | refused without `--resolve`, as a target scan already refuses it |

Two more that needed no rule, but need saying in the man page:

- `--changelog all -H archived` is refused: HSM *state* is not in the record.
  What is there is the HSM *event*, as a record type — so "objects with an
  HSM event" is a type filter and "objects that are archived" is not.
- `--changelog all` with no `--since` starts at the oldest surviving record,
  which after a long gap without clearing is the whole log. Allowed, and
  worth a word in the man page rather than a refusal.

### 13.4 The whole option table, swept

`lfs_find_parse.c` defines **83 live options** (the commented-out entries in
that table are other commands' letters, kept for reference). Classified
against a changelog source, they fall into five groups, and the sweep found
three things the fourteen examples did not.

| Group | Options | Under `--changelog` |
|---|---|---|
| **Answerable from the record** | `uid`/`user`, `gid`/`group` (`CLFE_UIDGID`), `name`, `type` (creations only, §2.2) | allowed, **as recorded** |
| **Modifiers, no object state** | `print`, `print0`, `skip`, `help`, `lazy` | allowed; `lazy` does nothing without `--resolve` |
| **Object state — refused without `--resolve`** | `size`, `blocks`, `links`, `perm`, `projid`, `attrs`, `atime`, `mtime`, `ctime`, `btime`/`crtime`, `newer` and the 24 `newerXY`, `layout`, `pool`, `stripe-count`/`-index`/`-size`, the `comp-*`/`component-*` four, `mirror-count`, `mirror-state`, `extension-size`/`ext-size`, `foreign`, `mdt-count`, `mdt-hash`, `ls`, `printf`, `xattr` | refused, with the predicate named; answered from the lookup when `--resolve` is given |
| **Describe a walk** | `maxdepth`, `mindepth`, `threads` | refused always, as a target scan already refuses them |
| **Need the mounted filesystem's target list** | `obd`/`ost` | refused always: the record has no layout, so which OSTs hold the file is not a changelog question |
| **Ambiguous under this source** | `mdt`/`mdt-index` | **refused always** — see the fourth reason below |

**Three findings.**

1. **`--mdt` is refused outright, and §13.3 said it was free.** The reasoning
   there was that a record's MDT is the changelog it arrived in — but §8.3
   already says a rename that moves an object between MDTs appears in *both*
   changelogs, so the changelog an event arrived in is not always the MDT the
   object lives on.

   That leaves two readings of `--mdt 1` under `--changelog`: *events from
   MDT0001's log*, and *objects that live on MDT0001*. The first already has
   a spelling — it is the source selector, `--changelog testfs-MDT0001` — and
   the second is what `lfs find --mdt` means everywhere else. An option with
   two plausible readings is what these rules exist to prevent, so it is
   **refused under `--changelog`, with or without `--resolve`**.

   Nothing is lost: `--mdt` works normally under `--since`, where the answer
   is verified and the meaning is the usual one, and `--changelog MDT` selects
   a log. It also puts `lfs find --changelog` and `lfind` back in agreement,
   since a target scan refuses `--mdt` too.

   **This is a fourth reason to refuse**, beside no object state, no walk and
   no target list: *the record carries something that is not what the option
   means*. It is why `-name` is allowed and `--mdt` is not — the record's name
   **is** a name, recorded at the event, whereas the record's MDT is the
   identity of a log and not of an object. Under `--changelog` a predicate is
   answered from what the record carries, or refused; it is never
   reinterpreted into a neighbouring question.
2. **`--xattr` is allowed here, and refused on a target scan.**
   `find_device_supported()` refuses it because *"--xattr needs a mounted
   filesystem"* (`liblustreapi_pfind.c`) **[verified]** — and a changelog
   consumer with `--resolve` has one. So the same predicate is refused on
   `lfind` and accepted on `lfs find --changelog --resolve`, which is correct
   but needs saying, because it looks like an inconsistency between two
   commands that share their predicate parser.
3. **Grouping by parent FID is not a mode of this scanner at all.** An
   earlier draft made it a second coalescing key, and under it a record
   describes *a directory that had activity*, so `-type`, `-name` and `-uid`
   would silently start describing the parent rather than the object. The fix
   is not to hide the key from the CLI but to put it where aggregation
   belongs: a Filter Rule (§5.2). A flag that says `group by parent` may
   honestly emit directory records, because that is what it asked for; a
   coalescing key that quietly changes what a record describes may not.

Nothing else in the 83 conflicts. The three groups that refuse do so for the
same three reasons throughout — no object state, no walk, no mounted target
list — which is the property that makes the rule explainable in a man page.

### 13.5 The same flag, different sources — accepted, and stated

`--xattr` is refused by `lfind` because a target scan has no mount, and
answerable under `lfs find --changelog --resolve` because that one does. The
question is whether to level it down for symmetry. **No — accept it, and say
so in both man pages.**

The precedent is already shipped. `lfind --name` matches *"from the link
extended attribute, matching against every name a hardlinked object has"*
(`Documentation/man8/lfind.8`) **[verified]**, while `lfs find --name` matches
the name the walk arrived by. Same flag, different provenance, reviewed and
on Gerrit. `--xattr` is the fourth instance of an axis this project has
already taken.

**The invariant worth promising is not "the same flags behave identically
everywhere".** It is:

> A predicate is answered from what this source actually has, or refused. It
> is never approximated, and never reinterpreted.

Those two promises conflict, and the second is the one that keeps answers
true. Levelling `--xattr` down would make `lfs find` worse at something it can
do correctly, in exchange for a symmetry no user can act on: nobody runs the
same command against two sources and diffs the flag tables — they run one and
get an answer or an error.

What the difference obliges us to do instead:

| Flag | Namespace walk | Device scan (`lfind`) | Changelog (`--changelog`) |
|---|---|---|---|
| `-name` | the name the walk arrived by | every linkea name | the name recorded with the event |
| `-size` | glimpse, or SOM with `--lazy` | SOM only — `fp_lazy` is forced | glimpse or SOM, the caller's choice (§7.2.2) |
| `--xattr` | read through the path | refused: no mount | refused without `--resolve` |
| `-printf` | full | refused: no path | refused without `--resolve` |
| `--mdt` | the object's MDT | refused | refused (§13.4) |
| `--maxdepth` | the walk's depth | refused: no walk | refused; honoured under `--since` |

1. **Every refusal names its reason, not just the option.**
   `find_device_supported()` already does this — *"--xattr needs a mounted
   filesystem"*, *"-printf needs a path, which a target scan has not"* — so a
   user who hits one learns the rule rather than the exception.
2. **Each man page states what its source can answer**, in the shape of the
   table above, so the difference is discoverable before it is surprising.
   `lfind(8)` already has a "Differences from lfs find" section; this is the
   same section from the other side.

---

## 14. Validation

What a lab has to show before this is believable, in the order it should be
run:

1. **Event fidelity** — a known workload (create, write, rename, unlink,
   setattr, HSM) produces exactly the expected event set, with the right FIDs,
   parents and names.
2. **Restart** — stop mid-stream, restart at the last accepted index, and
   diff: no duplicates, no gaps.
3. **Coalescing** — 100 writes to one file inside `scp_min_age` produce one
   record and one lookup.
4. **The clearing contract** — with `_CLEAR` on, records before the last
   accepted index are gone and nothing after it is; with it off, nothing is
   purged.
5. **Absence** — with resolution off, a consumer asking for `--size` gets
   objects marked undecided, and the count is reported.
6. **Unlinked objects** — an object removed inside the window resolves to no
   attributes and is still delivered.
7. **DNE** — two MDTs, both changelogs read, and a rename across them appears
   in both.
8. **The default-mask trap** — `CL_ATIME` off by default is demonstrated, so
   the limit is on record rather than in a footnote.

---

## 15. References

- `lustre/utils/liblustreapi_chlg.c` — `chlg_dev_path()` `:32`, the reader,
  `llapi_changelog_start()`, `_start_user()`, `_clear()`
- `include/uapi/linux/lustre/lustre_user.h` — `changelog_rec_type` `:1901`,
  `changelog_send_flag` `:2071`, `changelog_rec` `:2100`, the extensions
  `:2114-2154`, `changelog_filter` `:2157`, `changelog_rec_offset()` `:2168`
- `include/uapi/linux/lustre/lustre_idl.h` — `CHANGELOG_DEFMASK` `:3062`
- `lustre/mdc/mdc_changelog.c` — the type-mask drop `:222`,
  `mdc_changelog_get_user_info()` `:722`, the filter ioctl `:786-820`
- `lustre/mdd/mdd_device.c` `:2352`, `lustre/mdt/mdt_handler.c` `:8220` —
  registration is server-side
- `lustre/utils/llsom_sync.c`, `lustre/utils/lustre_rsync.c` — prior art
- `include/lustre/lustreapi.h` — the record `:651`, the validity bits `:561`
