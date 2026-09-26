# 465bc31421 — LU-20611 lfs: find over a target, with --device

- **Commit:** `465bc31421c9` (465bc31421, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 6.5M tokens, $3.28, 6m36s

## Overall assessment

Looks good. One optional design question inline for whenever this is next refreshed; there's no need to re-spin for it.

## Findings

### 1. `lustre/utils/lfs.c` (line 6499)

(suggestion) This isn't a bug, but the sweep drops OSTs when --mdt is given, and yet it still hands them the layout predicates (--stripe-count, --pool, --layout, --comp-*, --mirror-*, --foreign, --ext-size). Those are just as MDT-only. For each OST, llapi_find_device() refuses them through find_asks_layout(), which returns -ENOTSUP with "the layout options need an MDT".

On a node serving both an MDT and OSTs:

    lfs find --fsname testfs --pool fast

the MDT gives a complete answer, and then every OST prints "failed for '<dev>': Operation not supported". The command exits non-zero, so a script can't tell this apart from a sweep that really failed.

The man page does document this. Still, should the sweep skip OSTs for layout options the same way it does for --mdt, and as the follow-on --paths change does? It could refuse only when no MDT is left, as it already does when scanned == 0.
