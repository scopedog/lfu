# 68288 `91527192`: the page described a lookup per object that does not happen

All three parts of the comment verified; all three fixed in the same commit as
`af2ef8f0`.

## What it said, and what the code does

The NOTES section read *"each FID is resolved through it by
`llapi_scan_rec_path(3)`"*. For an **MDT** target none is. `llapi_find_device()`
builds the directory map whenever `fp_fid2path_mnt` or `fp_paths` is set, and
composition uses the map wherever it has entries, with **no fallback** to a
lookup (`liblustreapi_pfind.c`, the `fc_dirmap != NULL` arm). What the mount
supplies on an MDT is the prefix and the fsname to compare with the target's
label. `llapi_scan_rec_path()` is reached only where there is no map — an OST
target, whose objects are named by their owner through the mount.

`lfind(8)` already says it correctly: *"on an MDT it always composes from the
map"*. The library page was the one out of step.

## The two smaller halves, both true

- **`fp_paths` was not documented at all**, though it is a public field that
  changes what the call prints and is the only way to name objects when the
  filesystem is entirely down.
- **`-ENOTDIR` and `-EXDEV` were missing from ERRORS.** `-EXDEV` was mentioned
  in the NOTES prose and `-ENOTDIR` nowhere, though `fp_paths` on an OST
  returns it by design.

## What the page says now

The NOTES open with what is true of both spellings — one pass builds the map,
pathnames are composed by walking it, there is no lookup per object and no
fallback, and an object the map cannot place (the root, or ancestors on
another MDT under DNE) is counted rather than printed. Then `fp_fid2path_mnt`
and `fp_paths` each get their own paragraph, and ERRORS gains `-ENOTDIR` and
`-EXDEV`.

checkpatch-man: no style problems; the patch's counts are unchanged.
