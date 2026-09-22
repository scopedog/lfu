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
