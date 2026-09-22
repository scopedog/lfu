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
