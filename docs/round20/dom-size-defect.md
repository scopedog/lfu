# A device scan answers `--size 0` for a DoM file — measured, not fixed

Found by the Gerrit AI on **68159 PS16** (`e6fb45c4`, marked *defect*).
Verified end to end on the lab. **Not fixed** — the reason is at the
bottom, and it is deliberate.

## What happens

    lfind --device <mdt> --type f --size 0    matches a 65536-byte file
    lfind --device <mdt> --type f --size +1   does not match it

Measured on the lab against a real DoM file:

    fid=[0x200000402:0x2e4:0x0]  realsize=65536  mdt=0
    --size 0   -> 1 match      (wrong)
    --size +1  -> 0 matches    (wrong)
    no size predicate -> 1     (so it is scanned; not a filter artefact)

It is a **wrong answer, not an undecided one** — the object is reported
as having size 0.

## The chain, each step confirmed against the tree

1. **`scan_size()` gives up.** For a regular file it takes the SOM path
   whenever the LOV xattr is present, and returns having set nothing when
   there is no SOM. The fallback to the object's own size is guarded by
   `!S_ISREG(...) || !(so_xa_valid & ...LOV)`, and a DoM file is a
   regular file with a LOV.

2. **A DoM file has no SOM in the ordinary case.** Confirmed on the lab:

       lfs getsom /mnt/lustre/ddom/domfile
       failed to get som xattr: No data available (61)

   SOM is absent while the file is still open for write — and `lfind.8`
   documents scanning a target **in service** — and absent entirely on a
   filesystem older than SOM.

3. **`find_get_stripe_count()` returns 0.** It takes
   `lmm_stripe_count` from the last instantiated, non-extension
   component. For this file the layout is

       lcme_flags: init    lmm_stripe_count: 0   lmm_pattern: mdt
       lcme_flags: 0       lmm_stripe_count: 1   lmm_pattern: raid0

   so the only `init` component is the DoM one, whose count is 0.

4. **`find_decide()`'s undecided gate does not fire.** It reads

       if (param->fp_check_size &&
           ((S_ISREG(mode) && stripe_count) || S_ISDIR(mode)) && ...

   With `S_ISREG` true and `stripe_count == 0` the gate is false, so the
   object falls through to `find_value_cmp()` and is answered against
   `stx_size`, which is still the 0 the record carried.

The gate's `stripe_count` condition is right for a **walk** — a file with
no OST stripes has its size on the MDT and the MDT answers. It is wrong
for a **device scan of that MDT**, where nothing filled the size in.

## Why it is not fixed here

The data really is on the MDT: `obj->so_size` is the answer for a
DoM-only file. But knowing the layout is DoM-only means walking the
composite LOV — checking `LOV_MAGIC_COMP_V1`, each `lcme_flags` for
`LCME_FL_INIT`, and each component's pattern for `LOV_PATTERN_MDT` —
and **the scan backend has no LOV parsing at all today**. It only tests
whether the xattr exists.

So the fix is a new parser over an untrusted on-disk structure, with the
bounds checks that implies. That is precisely the shape of the defect
68159 already carried once — `layout_swab_lov_user_md()` walking
`lcm_entry_count` and `lcme_offset` with nothing bounding them, which
`find_lmm_fits()` now guards.

Writing that at the end of a long session, verified against a single
hand-made DoM file, is not something to land in a public API. It wants
its own patch, its own bounds tests, and a sanity case with a DoM file —
which is the fourth item for the test patch already owed.

## The shape of the fix, for whoever takes it

In `scan_size()`, when there is no usable SOM:

- if the layout has **no instantiated non-DoM component**, the object's
  own size and blocks are the file's, and are **strict**, not lazy;
- otherwise leave it unset, as now.

Alternatively, and more cheaply, `find_decide()`'s gate could stop
requiring `stripe_count` for a record with no path — a device scan
cannot know the size of any regular file it has no SOM for, so
*undecided* is at least not a wrong answer. That does not report the
size a DoM file plainly has, so it is the weaker of the two.

## The other two findings on 68159, both fixed

- `16e4d680`: `llapi_find_device(3)` was built and installed but absent
  from `lustreapi.7`'s **Namespace Scanning** index, where both its
  siblings are listed. Added — at 68159's own state, where the list is
  two entries rather than the five it has at the tip.
- `40b1f807`: `scan_linkea_entry()` documents "Returns the entry count",
  but also returns 0 for an entry at `@idx` whose `reclen` does not fit
  the buffer — a different thing from "no linkea", and confirmed at the
  `return 0` on the bounds check. The comment now says both.
