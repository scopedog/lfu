# Batch 2, second pass on 68288 -- 2026-09-22

The one question the 09-21 re-review left, settled: **`--fid2path` falls back
to `llapi_scan_rec_path()` on a map miss** -- but only where that lookup does
not go to the target being scanned.

## The reviewer's premise, and where it breaks

The finding read:

> a `llapi_fid2path_at()` through that mount never touches the target being
> scanned -- so "a lookup asks a target that may be out of service" doesn't
> apply to it.

That is true for an OST and false for an MDT. `lmv_fid2path()` routes by FID:

    tgt = lmv_fid2tgt(lmv, &gf->gf_fid);      /* lustre/lmv/lmv_obd.c:661 */

so the RPC goes to the MDT that owns the FID. An MDT object's own FID is
owned by the MDT being scanned, and a device scan reads that MDT precisely
because it is stopped -- the client would wait for it in recovery rather
than answer. An OST data object is different: it is named by its owner's
FID, which lives on an MDT, so that lookup never asks the OST. The existing
comment in `llapi_scan_rec_path()` says as much for the OST case already.

## What was built

The fall back is taken when the map cannot place the object **and** the
lookup will not be sent to the scanned target:

  - `find_lookup_spares_tgt()` -- the target is in service, or the record
    carries `LLAPI_SCAN_OWNER` (an OST object, named through its owner).
  - `find_rec_may_have_name()` -- the class has a name somewhere at all.
    An object a target keeps for itself, a DNE agent inode and an orphan
    in PENDING have none anywhere, so they cost no ioctl to be told so.

"In service" is reported by the scan rather than guessed at: `scan_run()`
sets `pp_live` from the backend it chose, as `pp_live = kind is neither
LDISKFS nor ZFS` -- put that way round so a backend added later is in
service unless it says otherwise. `find_device_cb()` carries it into
`fc_tgt_live`; the changelog callback sets it true, the log having been read
from an MDT that is running.

Also taken from the 09-21 re-review: the `pp_ran` assignment moved below the
declarations it had been inserted above (its style finding), and the man page
brought in line -- `--fid2path` on an MDT looks nothing up unless that MDT is
in service.

Not taken, still: `sd_want` never narrowed by the pre-pass's `known` mask,
and the 256-byte `strncpy()` pad per dirmap insert. Both are performance and
want measuring.

## Measured on the clone VM, MDSCOUNT=2 ldiskfs

The fixture is a DNE shape the earlier round said this rig could not build
cheaply, and it takes four lines: `/mnt/lustre/b2g` on MDT0000, a remote
directory `b2g/remote` on MDT0001 (`lfs mkdir -i 1`), and files under it.
Their linkea parent is MDT0000's, so MDT0001's own map cannot place them.
Arms: **F** = `b2-tip`, **G** = this pass, **H** = G with the gate forced
open (`return true || ...`), the build the reviewer's suggestion would have
produced. Each arm's loaded `liblustreapi` was logged with `LD_DEBUG=libs`,
not assumed -- and the first attempt at G was the libtool *wrapper* and had
to be rebuilt from `.libs/lfs`.

**In service** (MDT0001 mounted, so the kernel backend reads it), scanning
it with `--fid2path /mnt/lustre` ([`b2g-live2.sh`](b2g-live2.sh)):

| arm | named | counted nameless |
|---|---|---|
| F (`b2-tip`) | **0** | 7 |
| G (this pass) | **3** -- the whole remote subtree | 4 |

G's three are `b2g/remote/rf1`, `rf2` and `remote/sub/rf3`: exactly the
names the mount could produce and the map could not.

**Stopped** (MDT0001 unmounted, MGS/MDT0000/OST and the client mount still
up, so `--fid2path` has a mount and the lookup *would* go to the stopped
target) ([`b2g-off.sh`](b2g-off.sh), [`b2g-ctl.sh`](b2g-ctl.sh)):

| arm | result |
|---|---|
| F | rc=0 in **0s**, 6 counted |
| G | rc=0 in **0s**, 6 counted -- identical to F |
| H (gate forced open) | rc=124, **killed at 180s**, nothing printed |

While H ran, the console filled with

    LustreError: target_handle_connect() lustre-MDT0001: not available for
    connect from 0@lo (no target)

which is the client waiting for the target being scanned. That is the
measured form of the premise the reviewer's finding rested on, and it is why
the fall back is gated rather than unconditional. `--paths` and a plain
device scan are byte-identical between F and G.

## What it changes, honestly

Beyond the in-service case above, on the offline configurations:

  - MDT, stopped, `--fid2path`: no lookup, as before the change.
  - MDT, in service (the kernel backend): the lookup is new, and needs
    `lfu.ko` -- 2.19 material, not testable here.
  - OST, `--fid2path`: an object with an owner is looked up as before; one
    without was already answered `-ENOENT` inside `llapi_scan_rec_path()`
    before any ioctl.
  - `--internal` on either: the internal objects no longer pay an ioctl to
    be told they have no name. Same output, fewer round trips.
  - the changelog and a namespace walk: unchanged, `fc_tgt_live` is true.

So the lab work here is non-regression, not demonstration. The behaviour the
change exists for is the in-service backend that LU-20722 and LU-20730 add
higher in this same stack.

## The lreview on the fixed commit, and the split it forced

Re-reviewed at `dfad74a166` (3 findings, one a defect):

1. **`*pp_live` can never be true at 68288.** Correct, and it matters:
   `SCAN_BACKEND_MAX` is 2 until LU-20722 adds the kernel backend, so at
   68288 the liveness test is a constant false and the MDT fall back is
   dead code the man page nonetheless promised.
2. The man page paragraph, for the same reason.
3. `--fid2path` and `--paths` have no EXAMPLES entry, where `--device`
   does. Taken -- one each.

So the fix is **split across the stack**, the way a change that depends on
a later commit has to be:

  - **c08 (68288)** gets the restructuring, `find_rec_may_have_name()`, and
    a fall back gated on `fc_dirmap == NULL` -- which is b2-tip's own rule,
    an OST having no map and an MDT's map answering or nothing does. Its man
    page says there is no MDT lookup, which is true of every backend that
    exists at that commit.
  - **c22 (LU-20722)**, which is what first makes an in-service target
    scannable, adds `pp_live`, `fc_tgt_live`,
    `find_lookup_spares_tgt()` and the man page paragraph about a target in
    service.

`genfix.py` now takes two trees and emits the two sets, and checks each
upper anchor against the stack **as the lower set leaves it**, not against
the raw commit. Confirmed after driving: `fc_tgt_live` appears 0 times at
c08 and c21, 4 times at c22 and c25.

## The lreview on the split, and what is left of it

`d3faad7f40`, 2 findings, no defects, "no need to re-spin":

1. **Taken.** The comment's opening paragraph was a leftover of the
   unsplit version -- it promised a lookup for what the map cannot place,
   while the guard right below it is `fc_dirmap == NULL` and the next
   paragraph said the opposite. Dropped from the lower variant; the upper
   one keeps it, where it is true again.
2. **Queued, not ours from this round.** The `--paths` explanation is keyed
   off `-ENOTDIR`, which the pre-pass answers through `pp_missing_rc` --
   but so does `scan_device_exists()` via `stat()`, so
   `lfs find --device /dev/null/x --paths` explains that an MDT has no
   directories when the real answer is that the path is not there. A second
   `bool` out on `struct scan_prepass`, next to `pp_ran`, would make the
   message fire only for its own case.

The lab numbers above were measured on `55c6aaddd9`, whose only difference
from the split tip is those 14 EXAMPLES lines.

## Method

`genfix.py` generates [`b2bfix.py`](b2bfix.py) from the difference between
`b2-tip` and the hand-edited tree, choosing each hunk's anchor by a rule
worth keeping: grow context, asymmetrically, until the old text occurs
exactly once in the tip **and** at most once in every commit of the stack,
preferring the anchor that matches the most commits. Symmetric context
picked anchors that existed only at the tip, and the per-commit build sweep
was what caught it -- three commits' worth of `has no member named
fc_tgt_live` before the anchors were right.

[`b2bdrive.py`](b2bdrive.py) rebuilds the 26 commits from `b1-tip` with
b2fix's transforms and these. Verified:

  - the driven tip's tree is **identical** to the hand-edited tree;
  - 26/26 per-commit builds clean (`sweep-b2b.log`);
  - checkpatch clean on the three batch-2 patches, the only findings being
    the standing `lustreapi.7` SEE ALSO noise.

## The lreview on LU-20722, and the ten fixes

`c7bab4f656` had never been reviewed with the liveness code the split put
in it. Ten findings, one defect, "a refresh looks warranted". All ten
taken. Full text in [`lreview-lu20722.txt`](lreview-lu20722.txt).

1. **The commit message.** `Test-Parameters: ignore` left the new
   server-side path with no CI at all, so it is now
   `testlist=conf-sanity env=ONLY=305` and the patch has a test to point
   at. The body also claimed the `-ENOTSUP` refusal was the new backend's;
   `find_device_nobytes()` refuses on what the *scan answered*, so it
   reaches an OST scan through the device backends too. Said so.
2. **(defect) `STATX_ATTR_NODUMP` on ZFS.** `libscan_zfs.c` declares
   `IMMUTABLE|APPEND` and nothing else, deliberately, so one file answers
   `lfs find --attrs d` the same whichever scanner read it. The kernel
   backend declared NODUMP as well and osd-zfs really does set
   `LUSTRE_NODUMP_FL`, so the bit came out -- the exact divergence the mask
   exists to stop. Dropped.
3. **`so_valid` claimed PROJID and BTIME unconditionally.** Both device
   backends gate theirs; `lr_valid` is the OSD's own LA_* mask and was
   being ignored. Now gated, so an inode too small for `i_crtime` answers
   "not known" instead of the epoch.
4. **An object with no LMA lost its FID.** The iterator's FID is on the
   wire whether or not the LMA was readable, and for such an object
   `os_convert_igif` makes it the IGIF. The generation is handed over as
   `so_gen`, the way a device backend does, so `scan_rec_class()` rebuilds
   the same FID -- guarded on the sequence being this object's own id and
   inside the IGIF range.
5. **The label parser.** Now as careful as `scan_ldiskfs_label()`: all four
   hex digits consumed, no kind flag at all when it is neither MDT nor OST,
   and `INDEX_UNASSIGNED` (0xffff) left as "not known yet" rather than
   reported as index 65535.
6. **`scan_lmv_is_striped()` read only the bytes.** The kernel ring sets
   `so_xa_present` for a master's LMV and `so_xa_valid` only for a shard,
   whose magic it rebuilds -- so a master read as "not striped" and its own
   size was reported as the directory's, where neither a device scan nor
   `ll_dir_ioctl()` reports one. Presence is the question now, the bytes
   the refinement.
7. **`*pp_live` was never written for an OST scan** -- it sat below the
   block that drops `pre` for a target of the wrong kind, and the directory
   map asks for MDT. Mine, from earlier today. Moved above it.
8. **The unsupported-option refusal ran per record.** What it tests is
   fixed for the whole sweep, and a target that delivered nothing never
   reached the callback at all, so the option went unmentioned and the
   search succeeded on a question it never asked. Said once, and again
   after a sweep that delivered nothing.
9. **`lustre.spec.in`** packaged a file in `%{_libdir}/@PACKAGE@` without
   owning the directory, where the three `*-osd-*-mount` packages declare
   it alongside. Added.
10. **The man pages.** `lfs-find.1` now lists the options a target in
    service refuses and says to stop the target to ask them;
    `llapi_scan_device.3` had said flatly that a scanned target is not
    mounted, and now describes the three backends, presence-not-bytes for
    the layout and the directory stripe, and that the in-service backend
    declares whichever attribute set its OSD's device backend does.

**conf-sanity 305** scans a target while it is mounted -- counts, `--paths`,
`-name`, and the `--stripe-count` refusal -- and skips where `lfu.ko` is not
there to read one.

Two of the fixes live in `libscan_kernel.c` from c22 and move into
`lustreapi_lfu_rec.h` when c25 extracts `scan_lfu_rec_to_obj()`. genfix.py
works from the tip's trees and only ever sees the header spelling, so the
libscan_kernel.c spelling is hand-written in
[`b2bextra.py`](b2bextra.py) -- the old-spelling-down, new-spelling-up
pattern. Confirmed after driving: those two apply at c22-c24 and the
generated pair at c25.

## conf-sanity 305, run

**PASS in 17s** on the clone VM, against the plugin rebuilt from the fixed
tip and installed to `/usr/lib64/lustre/scan_osd_kernel.so` -- the installed
`.so` beats the build tree, so a run against the September 17 one would have
tested nothing. Output: `a scan of the mounted lustre-MDT0000 named 20
objects`, and the `--stripe-count` refusal held.

**The first run skipped**: `Need MDS >= 2.17.58`, and the rig's modules are
`2.17.57_206_g6a13016`. That guard is the one all of 300-304 carry, so none
of this block runs here without a full module build. The passing run had the
guard removed **in the VM's working copy only** ([`conf305b.sh`](conf305b.sh));
the committed test keeps it. The script's EXIT trap did not fire, so the file
was restored from git by hand and checked: guard present, test present,
working tree clean. What is proven is the test body against a real mounted
target -- the thing that would have broken in Maloo -- not the version gate.

## The second lreview on LU-20722: seven more, five taken

`ff9f8a36cf`, 7 findings, one defect. **One was mine from an hour earlier:**
reading presence as striped also reads a *foreign* directory as striped,
since `trusted.lmv` holds `LMV_MAGIC_FOREIGN` too and the module sets
`LFU_REC_HAVE_LMV` for it -- so a live MDT leaves its size unanswered where
a device scan reports it. Traded one divergence for a smaller one.

**Taken (5):**

1. The commit message did not mention the naming half at all -- `pp_live`,
   `fc_tgt_live`, `find_lookup_spares_tgt()` and the changelog's hard-coded
   true. It is user-visible and the man page documents it, so the hunk read
   as unrelated. Said.
4. The refusal text asserted "a target in service", but it fires on
   `lfsp_got`, so a **stopped** OST read off the device lands there too --
   an OST scan never answers `LLAPI_SCAN_LAYOUT`. Now it says what the scan
   does not carry without claiming why, and lfs-find.1 with it.
5. The `-links` undecided count ran *before* the prefilter, so
   `-type f -links +1` reported every directory on the target as undecided.
   Moved below it.
6. `so_xa_present` took over `so_padding[1]` and nothing versioned the
   plugin interface: a `scan_osd_*.so` built before it leaves the field
   zero, which reads as "no layout" and reports a striped file's MDT inode
   size as the file's own, silently -- and the `$LUSTRE` fallback loads
   whatever a build tree has. Each plugin now exports `scan_<name>_abi` and
   the loader refuses one that disagrees.
7. Two `if SERVER` blocks in `Makefile.am` where one does.

**Left, on the board:** (2) the released-file check still goes through
`scan_xattr()`, so on the kernel backend a released file gets no
`STATX_SIZE` at all, or the pre-release `stx_blocks`; and (3) the foreign
directory above. Both want one more bit in `lr_lfu`, set where
`lfu_fill_xattrs()` already has the bytes in hand -- a change to the module
and the wire format, in a commit of its own, and LU-20722 is 2.19 material
that gates nothing today.

## The defect fixed: two bits on the wire

`scan_size()` asked for the *bytes* of `trusted.lov` to decide whether a
file is released, and the in-service backend carries the layout as presence.
So `lov` was NULL and a released file fell into the SOM branch: with no
`trusted.som` nothing set `STATX_SIZE` at all; with one, `stx_blocks` was
the pre-release count. A device scan of the same MDT answers the inode size
and one block. The foreign-directory regression from the morning is the same
shape, so both are fixed together.

`lr_lfu` had room (bits ran to `0x80`), so:

    #define LFU_REC_LOV_RELEASED	0x100	/* every component released */
    #define LFU_REC_LMV_FOREIGN	0x200	/* the trusted.lmv is a foreign one */

The fill already has the bytes in hand where it sets `LFU_REC_HAVE_LOV`, and
already reads the LMV magic one branch below for the shard case, so setting
them is two conditions and a helper. The helper mirrors
`scan_lov_released()` line for line -- following `lcme_offset` to each
component rather than reading a pattern off the entry, which is what the
first attempt got wrong and the module build caught
(`lov_comp_md_entry_v1 has no member named lcme_pattern`).

**Where it lands.** The header and the fill belong to **c21** (LU-20720),
which introduces both; the consumer half to **c22**. genfix.py grew a
per-file `since`, `PROD = c21` against `LIVE = c22`, for exactly this. And
the fill has two spellings again -- inline in `lustre/lfu/lfu_ring.c` at
c21-c22, extracted into `dt_otable_lfu_rec()` in
`lustre/obdclass/dt_object.c` from c23 -- so the ring spelling is
hand-written in [`b2bextra.py`](b2bextra.py) and the `dt_object.c` one
generated. Confirmed after driving: the ring hunks land at c21 and c22, the
`dt_object.c` hunks at c23 and up, the header bits from c21.

**The residue, documented in the header rather than hidden:** the fill sets
`HAVE_LOV` on `-ERANGE` too, so a layout too large for the xattr buffer is
present and unjudged. The bit's absence therefore means "not known to be
released", not "not released", and such a file keeps the old behaviour.

**Verified:** 26/26 userspace builds; **the kernel modules build at c21**
and at the tip, on the clone VM, which is the only place configured for
them -- the local tree is `--disable-modules`, so the sweep never would have
caught the `lcme_pattern` error; checkpatch clean on all three changed
commits (c21's seven warnings are pre-existing `lfu_ring.c` ones);
tip tree identical to the hand-edited tree.

## The lreview on c21 (LU-20720): severity high, nine findings, all taken

`e9525db572`, the commit that introduces the ring and the wire record, had
never been reviewed with the bits added to it today. Three defects.

**(1) and (2), two races in the ring's end of stream.** The reader loaded
`avail` and then `done`, so a producer that advanced `head` and only then
set `done` between those two loads gave the reader a clean EOF with records
still in the ring -- the window opens exactly once per scan, when the reader
catches up. And `r->err` was a plain store before `WRITE_ONCE(r->done, 1)`
with no acquire on the read side, so a scan that ended in `-ESHUTDOWN` could
be reported as a clean EOF on a weakly ordered CPU. Now `done` is read
first with `smp_load_acquire()` and published with `smp_store_release()`.

**(3) a failed xattr read is not an absent one.** The fill's comment claimed
a clear `LFU_REC_HAVE_LOV` reads as "not answered"; the header says it means
"the object has a trusted.lov", so an `-EIO` built a record identical to a
file with no layout and a consumer took the MDT inode's size for the file's.
A third bit, `LFU_REC_XA_INCOMPLETE`, now says the HAVE_* bits are not a
complete answer for this object, and `scan_size()` leaves the size
unanswered rather than guessing.

**(4) and this is the one that matters for this morning's work:** the xattr
scratch was **64 bytes**. A `lov_mds_md_v1` is 32 plus 24 a stripe, a v3
with a pool name is 48 before its first, and every composite layout is
larger again -- so they all came back `-ERANGE`, the released question went
unanswered, and the `LOV_MAGIC_COMP_V1` arm of the helper written an hour
earlier was unreachable. `LFU_REC_LMV_FOREIGN` had the same hole for a
foreign value over 48 bytes. **The fix as first written was very nearly
inert.** `DT_LFU_XA_BUFLEN` is now a page. The read costs the same either
way -- the OSD has located the xattr by the time the size is compared, so
what changes is how much is copied out of a block it already holds, not
whether the block is read.

The rest: the producer kthread is named for its target, a bad `ring_size` or
`batch` says which and why instead of a silent `-EINVAL`, `LFU_REC_MAX` is
in the uapi header where a consumer sizing a read buffer will look for it
(and no longer duplicated in `lfu_ring.c`), and the two man4 pages point at
`lfu.batch(4)` and `lfu.ring_size(4)` rather than `batch(4)` and
`ring_size(4)`, which `man` would not find.

**Verified:** 26/26 userspace builds; **modules built at c21 on the clone
VM**; checkpatch 0 errors, and c21's warnings went 7 -> 9, the two new ones
being the "review error messages" class the file already carries for its
existing `CERROR`. Tip tree identical to the hand-edited tree.

## lreview on 68415 and 68416 — batch 2's last gate item

Their trees were settled by the AI round, so the reviews were finally worth
running. **68415: 4 findings, one defect. 68416: 2 findings, no defects
("neither needs a new revision on its own").** All six taken.

### The defect: _CLEAR could purge a record no callback saw

In event mode a rename over an existing name is **two objects under one
`cr_index`**, and `scan_cl_deliver()` moves `sl_accepted` to that index after
each acceptance. Traced through the code before fixing:

    scan_cl_event():  deliver(fids[0]) -> sl_accepted = cr_index
                      deliver(fids[1]) -> callback stops
    the read loop:    if (crc != 0) { sl_stop_rc = crc; rc = 0; break; }
    llapi_scan_changelog(): if (rc >= 0) scan_cl_clear(sl, true)

so the clear runs through `cr_index` — the record whose *second* object the
consumer never took. The cache is empty in event mode, so
`scan_cl_held_first()` returns 0 and does not hold it back either. That is
exactly what llapi_scan_changelog.3 says cannot happen, "never ahead of the
consumer".

`scan_cl_event()` now saves `sl_accepted` before the loop and puts it back
if any object stopped: a record is consumed only when all of it is.

### The rest

- **68415** the lazy `AT_STATX_DONT_SYNC` read moved *after* the
  revalidating `statx()`: `ll_getattr_dentry()` skips revalidation for
  `DONT_SYNC` and `llapi_open_by_fid_at()` sends no RPC for a cached inode,
  so read first it answered from this FID's previous resolve and the
  revalidation this call pays for never reached the size.
- **68415** `test9` added — `sc_type_mask` **with** a user, which is the one
  case that reaches `llapi_changelog_start_user()`, since the library calls
  it only when the mask is set. Until now sanity 157d's comments described a
  path the binary never ran.
- **68415** the summary names its entry point:
  `llapi: llapi_scan_changelog(), a changelog as a stream`, the shape c25
  already uses, so `git log --grep llapi_scan_changelog` finds it.
- **68416** `llapi_find_device.3` said "Four fields are the search's to
  decide" where the kernel-doc says five; `lfsp_got` is now listed, with the
  reason it is cleared rather than filled.
- **68416** `<libgen.h>` moved after `<getopt.h>`.

**Verified:** tip `7f9b243c26` identical to the hand-edited tree, 26/26
per-commit builds, checkpatch 0 errors on both (the recurring
"1 errors, 45 warnings, 215 lines" is the standing `lustreapi.7` noise).

## 09-23: conf-sanity 300 red in CI, and two `since` values

**What CI said.** On every ldiskfs run of 68160, 68163, 68288, 68415 and
68416, conf-sanity 300 failed with "lfs find did not refuse fsname_too_long
as a name". The Janitor gave CR-1 on 68160 and 68163. ZFS passed.

**Why.** `lfs find` did refuse the name. It said so in a new way: the AI
round moved `--fsname` to `llapi_name_verify()` (`parse-live-1`, c06), which
prints `filesystem name '...' longer than maximum 8 chars`. The test's grep
for the new wording (`conf-live-1`) was generated with `since=LIVE`, so it
only reached c22 and up, none of which is pushed. The 68160 reply "conf-sanity
300's grep moved with it" was true of the tip and false of what we pushed.

**The audit.** Every c21/c22 transform whose old text is already in a lower
commit was listed (26) and read. 24 belong to LU-20722 and stay. The other
one is `zfs-live-0`: `zfs-live-2` calls `isalnum()` from c07 but last
night's edit moved `#include <ctype.h>` to c22. It compiled only because
another header pulls it in. Both are back where they belong (c06, c07), and
genfix.py has a `SINCE_MARKERS` entry for each, so a regeneration keeps them.

**The driver.** `b2bdrive.py` now pins `GIT_COMMITTER_DATE` and takes an
optional PREV_TIP: a commit whose tree, parent and message match the one at
the same position there is reused. Driven against `39a4eb18d0` (what is on
Gerrit): c00-c05 **reused, same SHAs as Gerrit**; c06 differs by the grep,
c07-c21 by the grep and the include; c22-c25 trees identical. Two drives
give the same tip, `ae25cffdf8`. (The first try reused nothing: commit-tree
normalises the trailing newline, so the messages are compared rstripped.)

**Verified:** 26/26 per-commit builds, plugin macro check clean.

**Lab: conf-sanity 300 PASS (40s)** on the clone VM at the new c06
(`4baedd408c`, 68160), fixture untouched. Getting a fair run took three lab
traps, all in the rig and none in the code. The first two runs segfaulted in
`scan_ldiskfs_open()`, at a step CI had passed on the same commit:
- `.libs/lfs` has a DT_RPATH to `~/lfs68160-inst/lib`, so it loaded a 09-13
  liblustreapi: fixed with an LD_PRELOAD wrapper for `lfs` and for the
  scanner.
- This build's `PLUGIN_DIR` is `~/lfs68160-inst/lib/lustre`, not
  `/usr/lib64/lustre`, and holds a 09-11 `scan_osd_ldiskfs.so`: fixed by
  building c06's plugin by hand and bind-mounting it over that path for the
  run only (checksums logged before, during and after).
- A failed run leaves `lfsc` mounted and the next one aborts, so the wrapper
  now runs llmountcleanup first.
Before the run, c06's `lfs find --fsname fsname_too_long` printed CI's exact
message: `filesystem name 'fsname_too_long' longer than maximum 8 chars`.
Checkpatch totals on c06 and c07 are the same as their pushed versions.

## 09-23: lreview on c06 and c07

[`lreview-68160-0923.txt`](lreview-68160-0923.txt) (4 findings, $2.70) and
[`lreview-68163-0923.txt`](lreview-68163-0923.txt) (2 findings, $3.72), both
severity low. All six were checked against the tree and all six are real.
The user took the recommendation: fix 1, 3, 5; reword for 4; fix 2 with a
lab check; document 6 and defer the fix.

1. **c06 message** named `llapi_name_validate()`; the code calls
   `llapi_name_verify()` since the AI round. Fixed.
2. **c06, a block-device node stored on Lustre** was taken as a target by
   `lfs_find_is_device()`. Now skipped when `statfs()` on the path says
   Lustre; lfs-find.1 says so. `statfs()` on a node reports the fs holding
   the node, so a real `/dev/...` is unaffected.
3. **c06, lfs-find.1 `--local`** said only a missing backend ends the sweep;
   the code stops on any `ENOTSUP`. Reworded.
4. **c06, `fp_device`/`fp_target`/`fp_fsname` in public `struct
   find_param`.** Declined as a refactor (c06-c10 would all move). The
   header comment's "nowhere but here" claim was false and is replaced by
   what is true: only lfs uses them, the library ignores them. c07 re-wraps
   that comment when it adds `--search`, so it needs a second transform --
   the first drive showed the c06 one applying at c06 only.
5. **c07, the `enum scan_backend_kind` comment** predated the leading-slash
   rule. Rewritten to match `scan_backend_kind()`.
6. **c07, a nested scan of the same ZFS pool** skips the EBUSY checks while
   the in-process import is still loaded. No in-tree tool nests (lfs find
   closes each target first), so it is documented under `-EBUSY` in
   llapi_scan_device.3 and the fix is deferred.

All in [`b2cextra.py`](b2cextra.py), wired into genfix.py's output.
Driven against Gerrit's chain: c00-c05 reused, new tip `696b8c4419`,
tip-to-tip diff is exactly these five files. 26/26 builds, macro check
clean, checkpatch on c06 and c07 the same as their pushed versions (a first
wrap of the header comment was 81 columns, and was rewrapped).

**Lab, clone VM, new c06 `6f78341554` (code identical to the final c06):**
- conf-sanity 300 **PASS (38s)**.
- A block node on Lustre (`mknod b 240 99` under /mnt/lfsc): old lfs
  `failed for '/mnt/lfsc/blkab/node': No such device or address`; new lfs
  prints `/mnt/lfsc/blkab/node`, rc 0.
- A real block device (`losetup -r` of the MDT image) with `--internal`:
  both arms scan it, 4 objects, first `obj:11`. Without `--internal` both
  print nothing, which a walk would also do, so that run proved nothing.

### The second lreview on c06

[`lreview-68160-0923b.txt`](lreview-68160-0923b.txt), on `6f78341554`: 4
findings, severity low, "none needs a re-spin", $3.02. None is about the
`statfs()` guard itself.
1. The commit message still said the device check is `stat()` alone.
   **Fixed:** half a line on the Lustre-stored node.
2. `--local --ost/--mdt` finds a target's role with `strstr("-OST")`, so a
   filesystem named e.g. `db-OST` puts its MDT through the OST filter, and
   the `ENOTSUP` break ends the sweep before the OST is read. Real, and
   already in this patch's code. **Held for the user:** a small helper
   reading after `strrchr(name, '-')`, which `lfs_find_label_of()` already
   does.
3. lfs-find.1 says the naming line is printed "where more than one target
   is read"; the code prints it where more than one is *found* (`nr > 1`),
   and conf-sanity 300 depends on that. **Fixed** the wording.
4. The public `struct find_param` fields again: **declined**, as decided
   above.

Final tip **`0938f1c9e6`**: c06 = `11ee45fd71`, c07 = `818ae5de64`. Only
lfs-find.1 and c06's message differ from the swept and lab-tested
`696b8c4419`; checkpatch totals unchanged.

### The `-OST` fix (user: do it)

`lfs_find_label_is(label, role)` reads the role after the last `-`, as
`lfs_find_label_of()` already does, and replaces the four `strstr()` tests
in `lfs_find_local_targets()` and the `--local --ost/--mdt` filter. Applied
c06-c25 (20 commits); no `strstr("-OST"/"-MDT")` of ours is left in the
stack, only upstream's in obd.c. Tip **`e8def2606b`**, c06 `127cf1fd05`:
26/26 builds, macro check clean, checkpatch unchanged; conf-sanity 300
**PASS (41s)** on the VM, with the `--local --ost/--mdt` sweep branch taken
(no "not sweeping" in the log). Not lab-tested with a `db-OST` filesystem
name; the helper's logic is the one `lfs_find_label_of()` already relies on.

## 09-23: Artem's review, finding by finding

Seven inline comments from ablagodarenko on 68094, 68095, 68156, 68159 and
68160, some from the TLC GitHub review bot checked against the current
patchsets, some from a conf-sanity run on a rocky10 cluster confirmed with
debugfs. 68160's is conf-sanity 300's grep, already fixed. Taken one at a
time in stack order, verified against the tree first.

### 1. 68094 (c00): stale bytes in `lmd_stx` -- CONFIRMED, FIXED

`convert_lmd_statx()` ORs `STATX_BASIC_STATS` into `stx_mask` and does not
clear `lmd_stx`. Two callers hand it a buffer full of other bytes:
- `convert_lmdbuf_v1v2()`: the V1 `lmd_st` is still there after the
  memmove, and `stx_mask` (16 bytes in) lies over the V1 `st_nlink`: a
  directory with 2048 links reads as `STATX_BTIME`.
- the ENOTTY branch of `get_lmd_info_fd()`: the name written for the ioctl
  is still there, so bytes 16-19 of a long name become mask bits.

**Reproduced locally** before the fix, on a plain local directory (the
ENOTTY path): `measurements-2026.csv` matched `lfs find -type f -B +20000`
(born over 20000 days ago) and `short.csv`, with the same timestamps, did
not. After: neither matches, and both are still found with no predicate.
Both arms were this tree's own build (no RPATH locally; the libtool wrapper
puts `.libs` first). The V1 path needs a pre-V2 server to reach, and has
not been run.

Fix as Artem suggested: those two callers clear `lmd_stx` before the
conversion, not `convert_lmd_statx()` itself, whose third caller runs after
the V2 ioctl and must keep the MDT's mask. One line in c00's message.
Transforms `c00-stx-*` in b2cextra.py, 26/26 commits. Tip **`747f07589d`**:
26/26 builds, macro check clean, c00 checkpatch unchanged.

### 2. 68095 (c01): an unreadable MDT index under `--mdt` -- CONFIRMED, FIXED

`scan_rec_gather_finish()` turns any `llapi_file_fget_mdtidx()` failure into
`fp_file_mdt_index = OBD_NOT_FOUND`, `rc = 0`, and nothing tests
`LLAPI_SCAN_MDT_INDEX`, so `check_mdt_match()` compares `OBD_NOT_FOUND`
against the list: `--mdt` drops the object silently, and under the
negation it is printed as not on that MDT. Before the series the error
went to `goto out`. `want` always keeps `LLAPI_SCAN_MDT_INDEX` under
`--mdt`, and a device scan under `--mdt` must be of an MDT with an index,
so every record there carries it: the guard catches only a real failure.

Fix is Artem's guard: under `--mdt`, a record with no index is left out
(`goto decided` inline at c01-c02; `return 0`, `find_decide()`'s reject,
from c03 -- a first draft had `return -1`, caught by reading the function
before driving). One line in c01's message. Tip **`902fca0065`**, 26/26,
checkpatch on c01 and c03 the same as pushed.

**Lab (clone VM):** a directory with `open.txt` (644) and `secret.txt`
(600, root), searched as nishida. Three traps before it measured anything:
- with `-type f`, `secret.txt` was the first object to reach the `--mdt`
  UUID setup, whose open failed with EACCES for the whole directory;
- **`! --mdt` is a no-op in every lfs, stock included**: the parser sets
  `fp_exclude_obd` for `-m` and nothing sets `fp_exclude_mdt` -- also so
  on upstream master. Upstream's bug, not ours; to file.
- so the A/B used one lfs, built with that line corrected in the VM's
  working copy only (reverted, and the tree rebuilt), against the old and
  the new library.

Result: old library, `! --mdt lfsc-MDT0000_UUID` printed
`/mnt/lfsc/mdtab/secret.txt`, which is on MDT0000. New library: nothing.
`--mdt` identical in both (the directory and `open.txt`).

### 3-6. 68156 (c02) and 68159 (c05): Artem's own fix, folded -- CONFIRMED, FIXED

His TLC commit `ae5a21241a` (fetched with `gh api`; the public URL 404s)
fixes three wrong answers from a device scan of an MDT. The user chose to
fold it in with his credit: a sentence in c02's and c05's messages and his
`Signed-off-by` under ours. Ported in [`b2dartem.py`](b2dartem.py): his code
and man text where they apply unchanged, with two changes of ours:
- **`scan_has_link()`**: bytes at c02-c21 (the device backends read every
  xattr in one pass, external block included on ldiskfs, the xattr
  directory on ZFS; `SCAN_EA_BUFS` is `LLAPI_SCAN_XA_MAX`, so the
  always-read link cannot crowd another out). **Presence from c22**: the
  kernel ring always sends the link (`dt_otable_lfu_rec()` reads it
  unconditionally) but one over `LFU_LINK_MAX` as presence only
  (`LFU_REC_LINK_BIG`), so his `scan_xattr() != NULL` would have demoted
  every file with a large link on an in-service scan; and an object read
  in part (`SO_XA_PARTIAL`) keeps its class.
- `size_elsewhere` declared at the top of `find_decide()`.
The `path == NULL` rule is safe on every record source: they all go
through `find_rec_to_lmd()`, which sets `OBD_MD_FLSIZE` from the record's
own `STATX_SIZE`.

Transforms: classification, DoM size and man text c02-c25 (24 commits),
the presence helper c22-c25, the undecided size c05-c25. Tip
**`22fa94968d`**: 26/26 builds, macro check clean, checkpatch on c02 and
c05 unchanged.

**Lab, a fresh `lfsd` filesystem** (reg.txt 1000 B on an OST, dom.txt
1000 B with `-E 1M -L mdt -E -1`), stopped, its MDT image scanned:

| | unfixed c06 | fixed c06 `feaec761bc` |
|---|---|---|
| visible regular files | 4: `[0xe:0x0:0x0]` (mountdata), `[0x200000400:0x1:0x0]` (update log), reg, dom | 2: reg, dom |
| dom.txt size | 0 (none reported) | 1000 |
| `-size 1000c` | reg | reg, dom |
| `-size -1k` | update log, dom | nothing |

conf-sanity 300 **PASS (38s)** on the fixed c06. At c08 (`3f0c4c547c`,
its own plugin built by hand), `--paths -type f` names `/t/reg.txt` and
`/t/dom.txt`, so gating `scan_linkea()` on the demand mask loses no name.
Not run: fix 3 on its own (with fix 2 in, the DoM file has a size), and
the in-service path at c22 (2.19, parked), whose helper was reviewed only.

All seven of Artem's comments are now addressed in the tree.

## 09-23: lreview on c00-c06 after Artem's round

Six runs, one at a time (`lreview-c0{0,1,2,3,5,6}-0923c.txt`), 20 findings,
about $21. c04 and c08-c10 only carry the fixes, and c07 changed only
comments and man text, so neither was reviewed again.

### The regression I made: the --mdt guard in find_decide() -- FIXED

lreview c03 (1), a defect. From c03 the `find_foreign_accepts()`
shortcut is `goto decide`, and a guard at the top of `find_decide()` ran
before it on a record that had never been gathered, so under `--mdt`
every unstriped directory taking the shortcut was dropped. At c01 the
guard came after the gather and the shortcut jumped past it. Moved back
to that spot in `cb_find_init()` for c03-c25; device scans do not need
it there (under `--mdt` their records always carry an index). This also
makes c03's "no behaviour change" true again, which was lreview c03 (2).

Lab, c08 old (`3f0c4c547c`) vs new (`02c228e728`), one lfs with the `-m`
negation corrected (working copy only, reverted), on lfsc:
- `! --foreign --mdt lfsc-MDT0000_UUID`: old printed only the two files;
  new prints `mdtab`, `sub1` and `sub2` as well.
- `--mdt`: the same in both.
- `! --mdt`, as nishida, root-only `secret.txt`: nothing in both, so
  Artem's fix still holds in its new position.
Tip **`2ad21b33d6`**: 26/26, macro check clean, c03 checkpatch clean.

### lreview c05 (2): -printf %Li on a target scan -- FIXED

An unstriped directory has no LMV stub on a target scan (the walk builds
one, `llapi_scan_get_lmv()`, with its MDT as `lum_stripe_offset`), so the
zeroed buffer printed 0 on every MDT; the foreign arm read
`fp_file_mdt_index`, which a device scan sets only under `--mdt`. Fixed in
the print alone: on a target scan, `%Li` for a directory with no LMV or a
foreign one prints the record's `lfsr_mdt_index`, or nothing if the scan
does not know it. Not by building a stub: that would change what
`--foreign`, `--mdt-count` and the hash checks see, which the finding did
not ask for. Transform `c05-li`, c05-c25; tip **`9b40ac0e17`**, 26/26,
macro check clean, c05 checkpatch unchanged.

Lab: a two-MDT `lfse` (MDSCOUNT=2), `d0` on MDT0000, `d1` and `d1/sub` on
MDT0001, stopped, both MDT images scanned with `-type d -printf "%LF %Li"`:
the walk says d0 0, d1 1, sub 1; the old c08 says 0 for all three; the new
c08 (`974573270c`) says 0, 1, 1.

### lreview c05 (4): the layout options over an OST -- FIXED

An OST scan never delivers a layout, so `find_rec_to_lmd()` read "none"
and the default was forged: `--stripe-count`, `--pool`, `--layout` and the
rest compared against a layout that was never read, rc 0. c22's
`find_device_nobytes()` already refuses this on `lfsp_got`, so the defect
lived in c05-c21 -- the commits being pushed. Fixed at c05:
`find_asks_layout()` (c22's list, without `--projid`, which an OST object
answers), and when one is asked the target is probed as `--ost`/`--mdt`
already do; an OST is refused with -ENOTSUP, a target the probe cannot
name answers as before. From c22 this fires before `find_device_nobytes()`
for an OST, which is harmless. c07 gives `scan_device_target()` the search
path, so the call has a second spelling there -- the first sweep broke
from c07 (7/26) until it did. One sentence in c05's message.

Tip **`7af134d9b9`**: 26/26, macro check clean, c05 checkpatch unchanged
(a first wrap of the `llapi_error()` was 83 columns).

Lab, the stopped `lfsd` images, old c08 (`974573270c`) vs new
(`9fb37d04ab`):
- OST `! --pool fast`: old 33 objects rc 0; new refused, rc 95.
- OST `--stripe-count 1`: old **0** objects rc 0, though reg.txt's object
  is of a 1-stripe file; new refused.
- OST `--projid 0`: 33 in both. MDT `-type f --stripe-count 1`: reg.txt
  in both.

### 68340 (LU-20643) folded into 68094 -- user's choice (b)

lreview c00 (3): our standalone 68340 patches the same two callers as the
morning's `lmd_stx` fix, and whichever landed second would conflict; it
also clears `lmd_lmmsize`, the length `llapi_get_lum_file_fd()` copies by,
which ours did not. The user chose to fold it in and abandon 68340.
Both callers now do 68340's one `memset()` of the record up to `lmd_lmm`
before `convert_lmd_statx()`, replacing the separate `lmd_fid` and
`lmd_stx` clears and the `lmd_lmmsize`/`lmd_padding` stores. c03 renames
the third caller in the ENOTTY comment, so that hunk has two spellings
(c00-c02, c03-c25). c00's bullet is rewritten and names LU-20643, and c00
takes 68340's `Fixes: 11aa7f8704c4`. Tip **`5d4033c318`**: 26/26,
c00 checkpatch unchanged; the `-B +20000` repro still matches nothing.

**Owed on Gerrit, not done:** abandon 68340 with a note pointing at 68094.

## 09-23 afternoon: AI round on 68163 PS22 and 68415 PS14

Six comments. Checked against the tree:
- 68163 `<ctype.h>` in libscan_zfs.c: already fixed this morning (c07).
- 68163 the two comments above `scan_device_exists()` and at the end of
  `scan_backend_kind()` predate the leading-slash rule: real, text, in
  the minor batch.
- 68163 `-ENOTSUP` ends the whole `--local`/`--fsname` sweep, which on a
  node with both ldiskfs and ZFS targets and one backend missing stops
  before the rest: real, a behaviour change, **held for the user**.
- 68415, three real ones, **FIXED** (below).

Maloo's Verified-1 on 68163/68288/68415/68416 is conf-sanity 300 in
review-dne-part-3: the grep already fixed this morning.

### 68415 (c09): three fixes

1. sanity 157d skips the binary's test9 (`-e 9`) when the MDS is older
   than 2.17.50: its filter goes through `KEY_CHANGELOG_USER`, which the
   server has only from 2.17.0 (LU-19296); the same gate as sanity 160w.
2. `llapi_scan_changelog()` refuses `sc_size > LLAPI_SCAN_PARAM_MAX_SIZE`,
   as its two siblings do and as its man page already said.
3. The stats copy rounds down with `scan_stats_whole()`, as the siblings.
All c09-c25 (17). Tip **`14ca21843e`**: 26/26, macro check clean, c09
checkpatch unchanged.

Lab:
- `sc_size` 8192, local harness: old library proceeds and fails opening
  the changelog (ENOENT); new refuses with EINVAL.
- `ss_size` 20, on the VM's lfsc with a registered user, old c09
  (`4e8cc53274`) vs new (`08646b2317`): old gave back ss_size 20 and
  `ss_emitted = 0xabababab0000000b`, half the count and half the caller's
  bytes; new gives back 16 and leaves ss_emitted alone.
- The binary as 157d runs it: pass, test9 included; with `-e 9`, test9
  is reported "skip". The version gate itself was not run: no pre-2.17
  server here.

### 68163: ENOTSUP no longer ends a sweep -- user: go ahead

`lfs_find_device()` broke out of a `--local`/`--fsname` sweep on the
first `-ENOTSUP`. With one backend per kind of target (c07) and the OST
refusing layout options (this afternoon), that stopped short: the rest
of the node was never read. The break is gone from c06; the code comment,
lfs-find.1 and c06's message say what is true now. Lab, a scratch `lfse`
(2 MDTs, 2 OSTs) with `--local --stripe-count 1 --type f`, old c06
(`4e3635fb2d`) vs new (`8ad538f2db`): both read both MDTs, find the same
3 files and return 95; the old one stops at OST0000, the new one goes on
to OST0001 and reports its refusal too. (A stale `ost2_flakey` dm device,
still mapped to `/tmp/lfsc-ost2`, made the first try mount lfsc's
OST0001; llmountcleanup cleared it.)

## The minor batch, 09-23 -- [`b2eminor.py`](b2eminor.py)

All from lreview c00-c06 and the AI rounds on 68163/68288/68416, each
checked against the tree first:
- c00 message: the limit as "4096 bytes" (the macro is internal); new
  code described as properties, not fixes against master; the test file
  and what tests 0-9 cover.
- c00 code: the `liblustreapi_scan.c` memset comment no longer gives a
  reason that stopped being true; `LLAPI_SCAN_MDT_MASK`'s "used to
  return zero"; llapi_scan_namespace.3 drops "the HLD" and names the
  callback's negative returns; a comment on Artem's test-400 assertion.
- c01 message: `Fixes: 501e5b2c8a47` (LU-18027) -- checked, in the base.
- c02: the message says why lstddef.h went (the 09-22 AI round: 27
  files for one ARRAY_SIZE), and the blank line it left is gone;
  llapi_scan_device.3 says shards are delivered as visible, that a
  device scan sets LLAPI_SCAN_HSM only for an object with trusted.hsm
  (the walk sets it with no states for any regular file -- documented,
  not changed: from c22 the ring carries no trusted.hsm, so "absent"
  would claim "never archived" for a released file), and that
  trusted.link is now always read, which Artem's fold had not said.
- c05: its message's IGIF paragraph (MDT0000 does build one, from the
  inode and generation); the NULL-path comment names the guards that
  exist (each checked in the code).
- c06: conf-sanity 300 runs `--target` and `--fsname --mdt` against
  mds1 while it is up (ldiskfs only), which a multi-node cluster had
  never reached; one error string shortened to keep checkpatch at 2.
- c07: the two routing comments after the leading-slash rule.
- c08: the directory-map figure (288-byte slots, a 2^21 table: about
  576 MiB, 864 MiB mid-grow -- the growth simulated to check it); lfs-
  find.1 gains lfs-fid2path(1) (a second spelling from c12, which adds
  lfs-changelog(1)); llapi_find_device.3's -EXDEV and NOTES say that
  fp_fid2path_mnt's filesystem is compared on its own.
- c10: the two "The last" sentences name their fields.
- `pp_live`: `int-live-4` had `since="c02"` from genfix's per-file
  default and left a dead field in c08-c21; it is LIVE now, with a
  SINCE_MARKERS entry so a regeneration keeps it there.
Held for the user: the pre-pass `!S_ISDIR` filter (68288, a performance
suggestion, to be measured).

Tip **`757ea661f1`**: 26/26 builds, macro check clean, checkpatch on
c00-c10 identical to their pushed versions. conf-sanity 300 PASS (41s) on
the new c06, the new block present in the script it ran.

## 68288: the pre-pass directory filter, measured (user asked 09-23)

The AI suggestion on 68288 PS16: the `--paths` pre-pass reads xattrs for
every object on the MDT, and its callback then drops all but the
directories. A `pp_filter` returning 1 for `!S_ISDIR` would skip them
before the xattr read, since both backends call `ss_prefilter()` first.

**Method.** A real MDT (dirdata, so the VM: stock e2fsprogs 1.47.0 here
refuses it) of a scratch `lfsf`: 300 directories x 1000 files made with
`createmany -m` (LMA and link inline, no LOV), 300,572 inodes. Arm A is
c08 `db91411dcc`; arm B is the same plus the filter (a 10-line patch in
the VM working copy, reverted after), `scan_dirmap_filter` present in B's
library only. `lfs find --device IMG --paths -type f -name nosuch`
(nothing printed), `/usr/bin/time`, the c08 plugin bound over the stale
one. `--paths -type f` output: 300,000 lines in both, identical.

**Result** ([`ppbench-0923.log`](ppbench-0923.log)):

| | A (now) | B (filter) | |
|---|---|---|---|
| warm, 20 alternating pairs, elapsed | 0.28 s (0.24-0.29) | 0.19 s (0.17-0.20) | B faster in 20/20 |
| warm, user CPU | 0.23 s | 0.14 s | |
| cold, 5 pairs, caches dropped | 0.40 s (0.38-0.49) | 0.30 s (0.29-0.30) | B faster in 5/5 |
| no pre-pass at all (reference) | 0.14 s | | |

So the pre-pass itself costs 0.14 s warm now and 0.05 s with the filter:
about **64% of its cost is the xattr reads of objects it throws away**.
The whole `--paths` search is 32% faster warm, 25% cold. 20/20 pairs is a
sign-test p of about 1e-6; the noise between pairs is +-0.02 s, far below
the 0.09 s effect. These files carry no LOV; a real file's layout sits in
the same inode area the read parses, so a real MDT should save at least
as much. Not measured: ZFS, and a DNE target.

**Taken (user, 09-23).** Folded into c08 as the measured patch: `pp_filter`
in `struct scan_prepass`, `scan_dirmap_filter()` set by
`scan_dirmap_prepass()`, and the pre-pass sweep running with it; one
paragraph in c08's message. c08-c25 (18); the only `struct scan_prepass`
declared outside `scan_dirmap_prepass()` is `= { 0 }`, so no caller hands
over a stray filter. Tip **`a32c4b074d`**: 26/26, macro check clean, c08
checkpatch unchanged. On the VM the driven c08 (`9d75455e31`) prints the
same 300,000 paths as the old c08 and times 0.20 s against 0.29 s in 6/6
pairs, which is the B arm.

## 68415 (c09): a busy object is delivered, not held for ever -- user chose (a)

lreview c09 (1), medium: under `COALESCE|FOLLOW|CLEAR`, an object changed
more often than `sc_min_age` goes back to the tail of `sl_aged` on every
event, so `scan_cl_flush()` (which stops at the first object not quiet
enough) never reaches it, the cache-full eviction (always the head) never
does either, and `FOLLOW` never reaches the end-of-stream flush. It is
never delivered, and its `co_first` caps `scan_cl_clear()` via
`scan_cl_held_first()` for as long as it stays busy, so the registered
user's backlog on the MDT grows until the changelog fills.

Fix, in `scan_cl_object_one()`'s re-seen branch rather than the flush (a
busy object is by definition one seen again, so the test is O(1) there,
where the flush would have to walk up to 100k entries per record): once
`co_time - co_first_time >= SCAN_CL_MAX_HOLD (6) x sl_min_age`, on the
stream's clock like the quiet test, the object is delivered (keyed, as
flush and eviction do) and unlinked; its next event starts a fresh entry
with a fresh `co_first`. New field `co_first_time`, set with `co_first`.
llapi_scan_changelog.3 says so under `sc_min_age`; one sentence in c09's
message. c09-c25 (17).

test10 in llapi_scan_changelog_test.c: a writer thread chmods one file
every 200 ms for 20 s (SETATTR is in the default mask), the scan runs
`COALESCE|FOLLOW` with `sc_min_age = 1`, and the consumer stops on that
file's record and notes whether the writer was still running. A marker
file 2 s after the writer stops keeps the unfixed library from waiting
for ever. Two traps on the way: `volatile` flags (checkpatch) became
`__atomic` loads/stores, and `"%s/busy"` into `PATH_MAX` failed the real
`-O2 -Werror` build with -Wformat-truncation -- **the sweep compiled the
test files without -O2 and could not see it; it now uses -O2.**

Lab, VM, lfsc, test10 alone (`-e 0,...,9`), a fresh changelog user and
test directory per arm (a first run reused `busy`, whose FID then had
events from the previous arm, and passed in 2 s for the wrong reason):
new 8.3 s pass, old 22.6 s fail "held until it went quiet", new 8.3 s
pass. Tip **`65937da9dc`**, c09 `115ec7a624`: 26/26 with -O2 tests,
macro check clean, c09 checkpatch the same as pushed.

## The fix-now group after lreview 0923d (user: fix now)

- c00: the subject names the function: `LU-20603 llapi: add
  llapi_scan_namespace()`.
- c05: its message no longer says "Before" of an earlier patchset; the
  `find_needs_lmv()` comment no longer says a target scan refuses -printf;
  `find_asks_layout()` moved above `find_device_targets()`'s comment, which
  it had split from its function.
- c06: lfs-find.1 says only one selector may be given, and that
  `--stripe-index` acts as `--ost` on a target.
- c08: lfs-find.1 says `CAP_DAC_READ_SEARCH` is for FIDs looked up through
  the mount (an OST's, always), not for an MDT's map; `find_decide()`'s
  comment moved back onto it from above the helper(s) inserted between
  (one comment, identical c08-c25, moved rather than the helpers, since
  c22 adds a second one there).
- c09: under `FOLLOW`, the scan ends on `sc_endrec` instead of waiting for
  a record past it; a shadowed loop variable renamed; "three pointers" is
  four, with `sc_got` named; test9 asserts the filter ran (CL_CREATE
  delivered, nothing but CL_CREATE and CL_MARK); 157d skips test6 when
  mds1 has another changelog user (counted on the MDS in the shell, since
  the binary runs on the client) as well as test9 on an old MDS.

Tip **`b7bf2a622d`**: 26/26 with -O2 tests, macro check clean, checkpatch on
c00/c05/c06/c08/c09 the same as their pushed versions (a first 157d line was
81 columns). VM, c09 `43836ae544`: the full test binary passes with one
user; the `changelog_users | grep -c "^cl"` count reads 1, then 2 with a
second user; `sc_endrec` = the current index with `FOLLOW` on an idle MDT:
old library still waiting at the 10 s timeout, new returns in 1 s with 59
records.

## Before the push: regression run, last lreview, and a sweep that lied

**Regression run at c10 (`244ed8b0d0` on the VM, the final code):** the
c10 utils installed into the VM's `~/lfs68160-inst` prefix (backup
`~/lfs68160-inst.bak-0923`; `/sbin/mount.lustre` was refused, correctly,
and left alone) and c10's plugin put in its PLUGIN_DIR, so the tree's
binaries load c10 through their own RPATH -- no LD_PRELOAD or bind of the
plugin. Test binaries bound over the installed 09-09 ones for the run.
- sanity 56 (MDSCOUNT=2, OSTCOUNT=2): **86 PASS, 0 FAIL**, 1 SKIP (56xc,
  2 GB free space). A first 2-OST run failed 15 subtests because ost2
  never started -- the framework reused the 1-OST images; `llmount.sh`
  with fresh images first fixed it.
- sanity 157c, 157d: **PASS**.
- conf-sanity 300, 301, 302, 303, 304: **PASS** (305 arrives at c22).

**lreview c09 (the final code):** a first run failed ("claude exited 1",
no output); the rerun: 6 low. Text fixed -- the subject names the
function (as c00's does), the message mentions `_FOLLOW` and `_ONCE`
(test5 confirmed to cover it), the "Three smaller things" paragraph that
described patchset history is gone, and the uid/gid comment says who
acted. Held: the lazy-size question (already held) and filling the
record from `struct statx` directly.

**The sweep was sweeping the wrong tip.** build-sweep-b2b.sh carried a
literal range, updated by a `sed` of the previous SHA. After `ef896a898b`
one update missed and every later one matched nothing, so every "26/26"
reported for `a32c4b074d`, `a684772d41`, `140060a3b6`, `65937da9dc`,
`1725b772b1` and `b7bf2a622d` rebuilt `ef896a898b`. The VM builds of
c08/c09/c10 did compile the real code in between. Found while updating it
for the final tip; the script now takes the tip as an argument and prints
the range it sweeps. **Final tip `4966ac5055`: 26/26 for real**
(`SWEEP b7b1332a42..4966ac5055, 26 commits`), -O2 test compiles, macro
check clean.

**68163's Test-Parameters (user, 09-23):** the bare `testlist=sanity
env=ONLY=157c` is dropped under Andreas's rule (the default review testing
runs 157c); `fstype=zfs testlist=conf-sanity env=ONLY=300` stays, and the
message paragraph that spoke of "the two sessions" now speaks of one.
Message-only: every tree is identical to the swept `4966ac5055`. Final tip
**`0ef719269e`**, c10 `5b1c87cba0`.

## PUSHED, 2026-09-23 (user: "then push")

`git push review 5b1c87cba0:refs/for/master` from `~/projects/lustre/
lustre-scanfid`, tagged `b2c-pushed`. Gerrit's current revisions checked
against the pushed chain, all 11 identical:

| change | PS | | change | PS |
|---|---|---|---|---|
| 68094 | 25 | | 68160 | 24 |
| 68095 | 26 | | 68163 | 23 |
| 68156 | 26 | | 68288 | 17 |
| 68157 | 26 | | 68415 | 15 |
| 68158 | 23 | | 68416 | 15 |
| 68159 | 23 | | | |

68231 (the base, master-next) untouched. **68340 ABANDONED**, pointing at
68094. **19 replies posted** (7 to Artem, 12 to the AI) on the patchsets
their comments were written on; read back: 19/19 threads resolved with
our reply last. Not posted: Artem's three older 68094 threads (PS18
struct-in-man-page, PS21 test-400, PS21 "overkill"), which want a
sentence from the user.

The VM's `~/lfs68160-inst` now holds c10's utils and plugin (backup in
`~/lfs68160-inst.bak-0923`), so the tree's binaries there load c10.
