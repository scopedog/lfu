# The plan to 2.18

**Date:** 2026-08-19 · **Constraint:** userspace tools target Lustre 2.18, the
in-kernel OSD scanner targets 2.19 (Andreas, 2026-08-19) ·
**Build order:** [`architecture.md`](architecture.md) §12

Master is `2.17.56`, the development series that becomes 2.18.0. So 2.18 is a
**deadline**, not a sequence: anything that ships in it has to be reviewed and
landed before feature freeze. That is the argument for landing pieces one at a
time, and against holding them for a larger series.

---

## Where it stands

| | State |
|---|---|
| LU-20603 · [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | patchset 2, `Verified+1`, **no human review**. Local commit ahead of it |
| LU-20605 · [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | patchset 2, `Verified+1`, no human review |
| LU-20606 · scanner | written, one commit, **unpushed** |
| LU-20611 · `lfind` | written, four commits, **unpushed** |

Seven local commits on `lu-20603-scan-api`. Everything is verified against
synthetic images and byte-comparison; **nothing has run on a real MDT**, and the
lab was deleted on 2026-08-18.

The local LU-20603 commit is ahead of what Gerrit has by four things, each
found by building the next piece: `sr_projid` on both producers, an explicit
`LLAPI_SCAN_MDT_MASK`, a `sp_size` rule that lets the parameter struct grow, and
the man page's release (2.19.0 → 2.18.0). That is the incremental method
working, and the reason to keep 68094 unlanded a little longer.

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

**Still open:** Gerrit warns that three subjects run past 50 characters.

### The original order

1. **68094 + 68095**, carrying §A and the four fixes already made. This is also
   what the re-wrapped commit messages have been waiting for.
2. **LU-20606**, once §B has run.
3. **LU-20611**, once `sanity` 56\* is green.

Pushing 20606 and 20611 onto a series with no human review adds two more
changes nobody has looked at. The counter-argument is that the scanner is the
piece with the performance story, and it may be what prompts a review. Post §C's
comment first and see.

## E. The rest of 2.18, in priority order

1. **Aggregate / histogram Filter Rules** (step 4). Andreas named the bounded
   histogram as a requirement for the Trash Can tool, so this is a consumer
   blocker, not a reporting nicety. → **file a new Technical task** under
   LU-20462; it serves LU-19598.
2. **ZFS backend behind `llapi_scan_device()`** (step 3b). The cheapest test
   that the backend ABI generalises, which is the whole claim of the plugin
   split; the prototype's ZFS scanner already exists to port. → **file a new
   Technical task** under LU-20462.
3. **Named consumers.** The Trash Can already has a ticket and an owner —
   **LU-19598**, "TCU: Clean up files from the Trash Can", Emoly Liu — so this
   is coordination, not a filing: read the `ltrash_purge` patch and see whether
   `lfind`'s output can back it. PCC-RO has no ticket of ours; **file one** if
   the window allows.
4. **Changelog Input Scanner** (step 5), if the window allows. → **file a new
   Technical task** under LU-20462.
5. **Object Stream encoder** in userspace. The format is Andreas's call and is
   between FlatBuffers and Cap'n Proto; the encoder is ours once it is chosen.
   → **file when the format is settled**; the decision itself is LU-20462.

**Tracked, not ours to schedule:** **LU-20602** (MDT-internal objects carry no
LMA flag) is filed and assigned to us as an Improvement. Until it lands, three
internal objects classify as visible, which `lfind(8)` documents. It does not
block anything in this plan.

## F. Parked for 2.19

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

**To file, in this order:**

1. Aggregate / histogram Filter Rules — Technical task, parent LU-20462, `llapi` + `utils`
2. ZFS backend behind `llapi_scan_device()` — Technical task, parent LU-20462, `utils`
3. Changelog Input Scanner — Technical task, parent LU-20462
4. PCC-RO consumer — only if the 2.18 window allows
5. Object Stream encoder — once Andreas settles the format
