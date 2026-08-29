# The plan to 2.18

**Date:** 2026-08-19, **revised 2026-08-24** · **Constraint:** userspace tools
target Lustre 2.18, the in-kernel OSD scanner targets 2.19 (Andreas, 2026-08-19,
reaffirmed 2026-08-24) · **Build order:**
[`architecture.md`](architecture.md) §12 · **Gap analysis against the HLD:** §E

Master is `2.17.56`, the development series that becomes 2.18.0. So 2.18 is a
**deadline**, not a sequence: anything that ships in it has to be reviewed and
landed before feature freeze. That is the argument for landing pieces one at a
time, and against holding them for a larger series.

---

## Where it stands

**As of 2026-08-24**, nine changes on Gerrit, all current, all with zero
unresolved comment threads:

| Change | Ticket | PS | Carries |
|---|---|---|---|
| [68231](https://review.whamcloud.com/c/fs/lustre-release/+/68231) | LU-20624 | 2 | the upstream `cb_get_dirstripe()` fd fix, found while building this |
| [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | LU-20603 | 8 | the record and `llapi_scan_namespace()` |
| [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | LU-20605 | 8 | `lfs find` on the record |
| [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | LU-20606 | 7 | `llapi_scan_device()` + the ldiskfs backend |
| [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | LU-20611 | 7 | the `cb_find_init()` split |
| [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | LU-20611 | 7 | the shared predicate parser |
| [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | LU-20611 | 7 | `llapi_find_device()` |
| [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | LU-20611 | 8 | `lfind(8)` |
| [68163](https://review.whamcloud.com/c/fs/lustre-release/+/68163) | LU-20613 | 6 | the ZFS backend |
| [68340](https://review.whamcloud.com/c/fs/lustre-release/+/68340) | LU-20643 | 1 | the reused-lmd-buffer fix, found by the round-9 review |

Base `5afbab284e`. Eight rounds of AI review answered, 43 replies posted.
**Verified on a two-backend lab 2026-08-24** — conf-sanity 165 PASS on both
ldiskfs and ZFS, `sanity` identical before and after across every test that
touches `lfs find` or `lfs getdirstripe`, and `lfs getdirstripe -r` measured at
EBADF 1 → 0. Still **no human review**.

---

## A. The contract, before 68094 lands — **done 2026-08-19**

All four items are in the local commits, awaiting the push in §D. What each
turned out to be:

| | Landed as |
|---|---|
| HSM state | `LLAPI_SCAN_HSM` (0x00080000), `sr_hsm_states` + `sr_hsm_archive_id`. The namespace producer calls `llapi_hsm_state_get_fd()` for regular files, demand-gated like the project id; the device producer reads `trusted.hsm`, whose `hsm_flags` are the same `HS_*` values the MDT returns and whose archive id narrows to 32 bits exactly as `mdt_hsm.c:262` does. Verified on a synthetic image carrying an archived and a released file |
| What the record is not | A paragraph in the header: an in-process record, not a serialization; it holds pointers and descriptors, so the Object Stream is a separate flat encoding |
| Filter intent | A paragraph on `sp_filter`: a callback is what an in-process consumer needs, and a filter crossing a process, network or kernel boundary is data rather than a function, expected beside it |
| LMR replica bit | Stated rather than reserved: mirrors are not distinguishable yet, LU-16742 and LU-17820 are the tickets, and a flag appends like everything else |

The device bits shifted up one to make room (`LLAPI_SCAN_INO` is now
0x00100000), which costs nothing while nothing has landed.

### The original list

**The only work here with an irreversible deadline.** `struct llapi_scan_rec`
and `struct llapi_scan_param` are exported: free to change now, an ABI event
after landing. Everything else in this plan is internal or new API and stays
cheap.

All of it amends **LU-20603** (68094), except where noted.

1. **HSM state.** `trusted.hsm` is tier 2 in the scanner design, PCC-RO and
   tiering are 2.18 consumers that need it, and the record has no field and no
   bit. One bit, one field, one tier-2 read. → **LU-20603** for the bit, the
   field and the namespace producer (an ioctl per object, so demand-gated like
   the project id); **LU-20606** for the device producer's xattr read.
2. **Say what the record is not.** It holds five pointers and two descriptors,
   so it can never cross a kernel or wire boundary; the Object Stream is a
   separate flat encoding. A paragraph in the header, not a design — it stops
   both the review question and the 2.19 surprise. → **LU-20603**
3. **Filter intent.** `sp_filter` is a callback, which serves an in-process
   consumer. A serializable filter is needed only across the kernel and RPC
   boundaries, so it is 2.19 work; state that the field is expected and leave
   room for it. → **LU-20603**
4. **LMR replica bit.** Reserve it, or accept it as an appended field later.
   The LMR tickets themselves are LU-16742 / LU-17820, neither of them ours.
   → **LU-20603**

**Open decision:** whether to ask Andreas first. Recommended: **both** — put the
question in the LU-20606 comment (§C, which is being posted anyway) and
implement in parallel. The field is small, and dropping one before landing costs
nothing if he wants a different shape.

## B. Verification — **done 2026-08-19**, all three green

Lab `lfu-scan-lab` (deleted when it finished), `c3-standard-8` in **us-east1-b** (every us-central1 zone
was out of capacity), Rocky 9.8, kernel 5.14.0-687.36.1, e2fsprogs
**1.47.3-wc2** — the version the scanner's build requires, straight from the
repo. All seven patches applied clean, ldiskfs enabled, 105 s build. Raw output:
[`bench-data/2026-08-19/lab-scan-results.txt`](../bench-data/2026-08-19/lab-scan-results.txt).

| Run | Result |
|---|---|
| **conf-sanity test_165** | **PASS.** *"scanned 108 objects; found all 102 visible FIDs"* — zero misses, six extras, which is exactly the predicted three `.lustre` entries plus LU-20602's three. *"lfind --type f found all 100 files"*. 7/7 contract tests on the MDT and 7/7 on the OST |
| **sanity 56\*** | **IDENTICAL** before and after: 75 pass, 2 fail, 9 skip both ways, and both failures (`56Eaa`, `56xb`) are present at the base commit. The parser move and the `cb_find_init()` split changed nothing |
| **sanity 157c** | **PASS**, 9/9 — including the two written today, `projid` and **HSM state** |

**What the build itself proved**, which no synthetic image can: `llapi_scan_device`
and `llapi_find_device` exported, `scan_ldiskfs.so` installed to
`/usr/lib64/lustre/` beside `mount_osd_ldiskfs.so`, `lfind` installed to
`/usr/sbin` by the `if SERVER` gate — and **`liblustreapi` links libext2fs zero
times**, which is the whole claim of the plugin design.

`--local` found both targets and scanned them in turn, `--target
testfs-MDT0000` resolved through `osd-ldiskfs.*.mntdev`, and a freshly
formatted OST is labelled **`testfs:OST0001`** — with a colon, the form that
before the review fix would have scanned as an MDT and returned nothing.

**Three bugs the lab found**, all in tests and all now fixed: the directory FID
in test_165 was read after `stopall`, when no client is left to answer; the
`grep` matching it was not `-F`, so a FID's brackets read as a character class
and matched every line; and `llapi_scan_test`'s test6 reused its counter after
the short-`sp_size` check, which only passes where there is no Lustre to scan.

### The original list

Rebuild a lab: `tests/lab-scan/` stages 01→04, about 40 minutes.

Each run is the proof obligation of a particular patch, so it carries that
patch's ticket; the lab itself is infrastructure and has none.

1. **`sanity` 56\*** — the whole proof that moving the parser and splitting
   `cb_find_init()` changed nothing. Nothing else substitutes for it.
   → **LU-20611**
2. **conf-sanity test_165** — the scanner's oracle: every FID the client sees
   must come off the device (→ **LU-20606**), and `lfind --type f` must return
   every regular file and no directory (→ **LU-20611**).
3. **`sanity` 157c** — re-run against the amended 68094, which has changed since
   its last Maloo run. → **LU-20603**
4. Opportunistic while a real MDT exists: `--target` and `--local`, which have
   only ever exercised their no-targets path (→ **LU-20611**); and a scan of a
   mounted, serving MDT, the torn-read case no synthetic image reproduces
   (→ **LU-20606**).

## C. Ticket hygiene — cheap, and it unblocks the review

Nothing here is hard; all of it is visible to the people whose review everything
else waits on.

- ~~Components~~ — **not a gap.** The LU project defines *no* components at
  all and no ticket in it carries one, ours or anyone else's, so the field
  cannot be set from the web either. This was an invented requirement, carried
  through four documents before anyone tried to act on it.
- **LU-20611's description** is the older block and renders mangled; the
  replacement is in [`tickets/lfind.md`](tickets/lfind.md). → **LU-20611**
- **The comment** has never been posted; it is in
  [`tickets/llapi-scan-device.md`](tickets/llapi-scan-device.md), and it is
  where the HSM question (§A) can ride. → **LU-20606**
- **The epic's description is stale** — it still says "FlatBuffers / MsgPack"
  when Andreas ruled MsgPack out on 2026-08-18 and added Cap'n Proto. It is the
  document everyone reads, and it is Artem's to edit, so this is a comment.
  → **LU-20462**
- Tell him the parent-FID-and-name item from his last round
  (`docs/local/…` A3/B1) is **done** at the record level. → **LU-20606**'s
  comment, since that is the change that carries it.

## D. Pushed — **2026-08-19**

All seven, rebased on `5afbab284e` (43 commits of master since the base, clean
rebase, none of them touching the refactored code, so the `sanity` 56\* result
still stands). Test numbers checked for collisions first: upstream `sanity` has
157a and 157b, and `conf-sanity` stops at 164.

| Change | Ticket | |
|---|---|---|
| [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | LU-20603 | patchset 3 — the contract work, the 2.18.0 man page, the re-wrapped message |
| [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | LU-20605 | patchset 3 |
| [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | LU-20606 | `llapi_scan_device()` |
| [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | LU-20611 | the `cb_find_init()` split |
| [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | LU-20611 | the shared parser |
| [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | LU-20611 | `llapi_find_device()` |
| [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | LU-20611 | `lfind(8)` |

**CI found one real bug, patchset 2 fixes it.** The Janitor reported *"Compile
failed"* on all five new changes: in a build without shared libraries — which
is how the builder configures — `PLUGINS` is off, so the backend is linked in
rather than dlopen'ed, and adding a plain `.a` to a *libtool* library's
`LIBADD` leaves its objects out of the static `liblustreapi.a`. Every program
linking that archive was short the backend's five symbols. The backend is now
compiled into the library in that configuration, and the separate archive
exists only where it becomes the plugin. Neither local build could catch it: a
client build has `LDISKFS_ENABLED` off, and the lab had shared libraries on.

**The "Merge Conflict" beside it is expected**, not a fault. This Gerrit has
`submit_type=CHERRY_PICK`, so each change is cherry-picked onto master alone:
68094 and 68095 apply cleanly, and everything above them edits regions those
two create, so a standalone cherry-pick has no context. It clears as the stack
lands from the bottom.

**Still open:** Gerrit warns that three subjects run past 50 characters. Left
alone deliberately — `notes/reference/gerrit_err.txt` is explicit that a
re-push costs ~30 sessions and ~150 hours of testing and risks an intermittent
failure, so cosmetic fixes wait for a refresh that is happening anyway. The
same reasoning rules out floating 68158 out of the stack to clear its conflict
flag: it would rewrite three changes for a flag that blocks nothing.

**When results arrive:** triage each failed session against other patches that
week, associate an LU ticket, and retest *only* that session — within 3–4 days,
before the cached build expires. `BUILD` as a patchset comment retriggers
Jenkins with no new patchset; `RECHECK` does nothing here.

### The original order

1. **68094 + 68095**, carrying §A and the four fixes already made. This is also
   what the re-wrapped commit messages have been waiting for.
2. **LU-20606**, once §B has run.
3. **LU-20611**, once `sanity` 56\* is green.

Pushing 20606 and 20611 onto a series with no human review adds two more
changes nobody has looked at. The counter-argument is that the scanner is the
piece with the performance story, and it may be what prompts a review. Post §C's
comment first and see.

## E. What the HLD still wants — gap analysis, 2026-08-24

Read against the LFU HLD, not in this repo (Andreas v0.1
2026-04-03, Artem's module diagram v0.2 2026-08-08). The diagram marks nine
boxes **mandatory (initial)**; everything dashed is Optional/Future and out of
scope for 2.18 by Andreas's decision to hold the OSD path to 2.19.

### Done

| HLD module | Ours |
|---|---|
| ldiskfs Device Input Scanner | 68156 |
| Lustre Namespace Input Scanner | 68094 |
| `lfs find` Filter Rule + its Output Format | 68095, 68157, 68158, 68159 |
| *(beyond the HLD's ldiskfs box)* | 68163 ZFS backend, 68160 `lfind(8)` |

### Not done, and mandatory-initial

| # | Module | Note |
|---|---|---|
| 1 | **Object Stream binary format** | FlatBuffers or Cap'n Proto. **Blocks 3, 4 and every cross-node use.** Decided off the 2026-08-18 meeting, not ours, **evaluation not started** |
| 2 | **Changelog Input Scanner** | The HLD names *three* initial input scanners — client mountpoint, ldiskfs, **Changelogs consumer**. We have two |
| 3 | **Changelog Output Filter** | Filter changelog events by attribute. *"There is currently no mechanism to filter Changelog events based on specific attributes"* |
| 4 | **Merge / Split Filter Rule** | Merge several input streams into one; split one into several. **This is what covers a DNE filesystem** — without it `lfind` does one target per invocation and nothing assembles the whole namespace |
| 5 | **Raw Write / Raw Read** | Persist the stream and read it back. *"facilitates testing, transferring scan results to other nodes, and asynchronous or post-processing"* — and it is how multi-node merge works before any RPC exists |
| 6 | **FID → pathname Output Format** | `fid2path()`. Verified absent from `lfind.c` and the scanner sources: `lfind` prints bare FIDs with **no way to get a path** |

### Not done, and not modules

**7. The performance target is met — with exclusive access to the device.**
*(Corrected 2026-08-24: an earlier revision of this section said the target had
never been tested. It was, on 2026-08-16.)* The HLD asks for *1M obj/s/MDT
assuming at least 1GiB/s read rate on the MDT device, exclusive of pathname
generation*.
[`measurements/cold-on-fast-storage-2026-08-16.md`](measurements/cold-on-fast-storage-2026-08-16.md)
ran exactly that, on a 1,406 MB/s NVMe stripe with 20M objects:

| | rate | 4e9 objects |
|---|---|---|
| **Option 1 — our userspace scanner** | **1,435,080 obj/s** at 1,313 MB/s | **0.78 h — meets it** |

That is **93% of the raw device**, reached with a single thread, because
`ext2fs_inode_scan` walks a block group's itable in large sequential runs.

**The condition attached to that number is the important part.** 93% of the
device means the scanner effectively has the device to itself — an unmounted
target, a snapshot, or a failover partner's LUN. On a serving MDT the scan
shares bandwidth with the MDT's own I/O and gets proportionally less; with a
snapshot it pays COW indirection on top
([`design-snapshot-scan.md`](design-snapshot-scan.md) §8).

**2.19 does not fix this.** After block parsing the in-kernel scanner also
reaches 99% of the same device
([`measurements/blockparse-2026-08-16.md`](measurements/blockparse-2026-08-16.md)),
so both scanners are device-bound and neither creates bandwidth. The OSD path
buys correctness on a live target, not throughput. **The HLD's 1M obj/s/MDT and
its ~1h/4B-object figure are offline numbers for any implementation** — worth
stating plainly, because they are easy to read as live-filesystem figures.

**8. The HLD's own test matrix**, from *Testing New Functionality*: Object
Stream encode/decode/structure tests, Output Format structure tests, and
*"Pathname generation from FIDs should be verified"*. Blocked on 1 and 6.

### Two risks, not tasks

- **The Object Stream is unowned and blocks three of the six.** It is the most
  likely thing to stall 2.18, and it is not something we can start.
- **2.18 has no story for scanning a live ZFS target.** 68163 handles exported
  pools only (`POOL_STATE_ACTIVE` → `EBUSY`), and the HLD's answer for ZFS was
  always the OSD scanner, now 2.19. Worth confirming this is understood as the
  shape of 2.18 rather than a gap someone expects us to close. See
  [`design-snapshot-scan.md`](design-snapshot-scan.md) for the one workaround,
  and why it is a poor one on ldiskfs and unavailable on ZFS.
- **What 2.18 actually delivers, stated so nobody infers more:** a scanner that
  meets the HLD's throughput target **on a target not in service** — unmounted,
  a snapshot, or a failover partner's copy — plus a client-side namespace
  scanner at ordinary `lfs find` speed. It does not deliver a fast scan of a
  serving filesystem, on either backend, and per §7 neither does 2.19 by
  itself: that needs bandwidth the MDT is not using.

## F. The rest of 2.18, in priority order — **revised 2026-08-24**

Derived from §E. The ordering rule is unchanged: what has a clock on it first,
what blocks other work next, what is merely wanted last.

1. **Object Stream format decision** — not ours to make, but **ours to chase**.
   It blocks Merge/Split, Raw Write/Read and the whole test matrix, and nothing
   else in this list can be sequenced around it. Escalate rather than wait.
2. ~~**FID → pathname Output Format.**~~ **Written and lab-verified
   2026-08-24**, held locally: `llapi_scan_rec_path()` plus
   `lfind --fid2path MOUNT`, conf-sanity 166 PASS on ldiskfs alongside 165.
   **Filed as LU-20637, pushed as
   [68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288)**; see
   [`tickets/fid2path-output-format.md`](tickets/fid2path-output-format.md).
3. **Merge / Split Filter Rule.** What makes a DNE filesystem scannable as a
   whole. Needs the format for the on-disk case, but an in-process merge across
   several `llapi_scan_device()` calls is useful before that and is a smaller
   piece. → **file a Technical task**, parent LU-20462.
4. **Changelog Input Scanner** + **Changelog Output Filter.** Named in the HLD
   as one of three initial input scanners, and the output filter has no
   equivalent anywhere in Lustre today. → **file one Technical task for both**,
   parent LU-20462.
5. **Raw Write / Raw Read.** Blocked on the format. Cheap once it exists, and it
   is what makes cross-node merge possible without any RPC.
6. ~~**The 1 GiB/s performance run.**~~ **Already done, 2026-08-16** —
   1,435,080 obj/s at 93% of a 1,406 MB/s stripe, 0.78 h for 4B objects. What
   remains is not a measurement but a statement: the HLD's target is an
   *exclusive-access* number, and our docs should say so wherever a reader
   would otherwise take it for a live-filesystem figure.
6b. **POSIX Input Scanner** — **written 2026-08-29**, held locally in 68094.
   Not a new module: `architecture.md` §7 had already established it is the
   namespace scanner with a different attribute source, and the walk's
   `ENOTTY` fallback meant it half worked already. What it needed was a
   *contract* — and enforcing it found a defect, a FID built out of the
   object's filename published with `LLAPI_SCAN_FID` set. See
   [`design-posix-scanner.md`](design-posix-scanner.md) and
   [`../tests/lab-posix/`](../tests/lab-posix/).

7. **Aggregate / histogram Filter Rules.** Andreas named the bounded histogram
   as a Trash Can requirement, so it is a consumer blocker rather than a
   reporting nicety — but the HLD's diagram marks Advanced Operators
   Optional/Future, so it sits below the mandatory set. → **file a Technical
   task**, parent LU-20462; serves LU-19598.
8. **Named consumers.** LU-19598 (Trash Can, Emoly Liu) already has an owner —
   coordination, not filing. PCC-RO has no ticket of ours; file only if the
   window allows.

### The original order, 2026-08-19 — superseded

1. **ZFS backend behind `llapi_scan_device()`** (step 3b). **Done**, LU-20613 /
   68163. **Promoted to first
   on 2026-08-19**, ahead of the histogram, because it is the only thing here
   with a clock on it: the cheapest test that the backend ABI generalises is a
   second backend, and running that test while LU-20606 is *in review* is what
   makes an ABI change free. The prototype exists to port, and its work unit is
   already object-ID ranges. → **filed as LU-20613** and **written**, see
   [`tickets/zfs-scan-backend.md`](tickets/zfs-scan-backend.md); lab-verified
   2026-08-19, held for review before pushing. The open question is answered
   conservatively in code: an imported pool is refused with EBUSY, so
   `lfind --local` on a serving ZFS MDS says so rather than guessing.
2. **Aggregate / histogram Filter Rules** (step 4). Andreas named the bounded
   histogram as a requirement for the Trash Can tool, so this is a consumer
   blocker, not a reporting nicety. Nothing forces it to be first, though — no
   review window closes on it. → **file a new Technical task** under LU-20462;
   it serves LU-19598.
3. **Named consumers.** The Trash Can already has a ticket and an owner —
   **LU-19598**, "TCU: Clean up files from the Trash Can", Emoly Liu — so this
   is coordination, not a filing: read the `ltrash_purge` patch and see whether
   `lfind`'s output can back it. PCC-RO has no ticket of ours; **file one** if
   the window allows.
4. **Changelog Input Scanner** (step 5), if the window allows. → **file a new
   Technical task** under LU-20462.
5. **Object Stream encoder** in userspace. The format is not our call and is
   between FlatBuffers and Cap'n Proto; **held 2026-08-19**, being decided off
   the 2026-08-18 meeting. The encoder is ours once it is chosen.
   → **file when the format is settled**; the decision itself is LU-20462.

**Tracked, not ours to schedule:** **LU-20602** (MDT-internal objects carry no
LMA flag) is filed and assigned to us as an Improvement. Until it lands, three
internal objects classify as visible, which `lfind(8)` documents. It does not
block anything in this plan.

## G. Parked for 2.19

The OSD API scanner and its `circ_buf` ring, the bulk RPC filter modules and
`OBD_CONNECT2_LFU`. Both are already designed and partly prototyped here.

**The kernel scanner has a ticket already, and it is not ours: LU-20591,
"Support iterating OSD objects via llapi"** (New Feature, WC Triage, Jinshan's
changes 68018/68019/68020). That is the same ground, and the measured comparison
with their filter is in
[`upstream/xiong-68020-filter-measured-2026-08-17.md`](upstream/xiong-68020-filter-measured-2026-08-17.md).
When 2.19 opens, the move is to join LU-20591 rather than file a competing
ticket. Bulk RPC and `OBD_CONNECT2_LFU` want a new ticket at that point.

The decisions they need — the wire format (**LU-20462**), the serializable
filter (with the aggregate ticket in §E, or LU-20462), and the resume protocol
after `LFU_REC_GAP` (**LU-20591** territory) — should be *settled* during 2.18
rather than implemented, so that 2.19 opens with them answered.

---

## Tickets at a glance

**Exist, ours:**

| Ticket | Carries |
|---|---|
| **LU-20603** · 68094 | the record and `llapi_scan_namespace()`; all of §A; `sanity` 157c |
| **LU-20605** · 68095 | `lfs find` on the record |
| **LU-20606** | `llapi_scan_device()`; the HSM read on the device side; conf-sanity 165's scanner half; the comment in §C |
| **LU-20611** | `lfind(8)` and the two refactors; `sanity` 56\*; 165's lfind half |
| **LU-20602** | internal objects carry no LMA flag — tracked, blocks nothing here |

**Exist, other people's — coordinate rather than file:**

| Ticket | Whose | Why it matters |
|---|---|---|
| **LU-19598** | Emoly Liu | the Trash Can consumer, already owned |
| **LU-20591** | WC Triage / Jinshan | OSD object iteration via llapi — the 2.19 kernel ground |
| **LU-20462** | Artem | the epic: format decision, stale description |

**To file, in this order — revised 2026-08-24 to match §F:**

1. ~~ZFS backend behind `llapi_scan_device()`~~ — **filed as LU-20613**, pushed as 68163, lab-verified on both backends 2026-08-24
2. ~~**FID → pathname Output Format**~~ — **LU-20637 / 68288**, pushed 2026-08-24, lab-verified
3. **Merge / Split Filter Rule** — Technical task, parent LU-20462. The DNE story
4. **Changelog Input Scanner + Changelog Output Filter** — one Technical task, parent LU-20462
5. Aggregate / histogram Filter Rules — Technical task, parent LU-20462, `llapi` + `utils`; serves LU-19598
6. PCC-RO consumer — only if the 2.18 window allows
7. Object Stream encoder + Raw Write/Read — once Andreas settles the format

**Chase, do not file:** the Object Stream format decision itself (LU-20462). It
blocks items 3, 7 and the HLD's test matrix, and it has no owner working it.
