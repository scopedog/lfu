# f3a40d5fce — LU-20637 llapi: name a device scan's objects

- **Commit:** `f3a40d5fcefd` (f3a40d5fce, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 4.6M tokens, $3.02, 5m43s

## Overall assessment

Looks good. One optional minor inline for whenever the patch is next refreshed; no need to re-spin for it.

## Findings

### 1. `lustre/utils/lfs.c` (line 6514)

(minor) With --paths a sweep now skips every OST, and --ost already skips every MDT, so a sweep given both matches nothing:

    lfs find --local --ost 0 --paths ...

This falls through to "no local OST to search" and -ENODEV on a node that does have OST0000 mounted, which points the user at the wrong cause.

If the patch is refreshed, could --ost with --paths be refused up front next to the "--ost and --mdt together match no target of a sweep" check, with a message saying that --paths only names MDT objects?
