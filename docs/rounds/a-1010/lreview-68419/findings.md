# HEAD — LU-20650 lfs: add find --since-cookie, a per-MDT anchor

- **Commit:** `304aa3dda793` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 2.1M tokens, $2.19, 4m45s

## Overall assessment

Looks good; the cookie read/check/write paths trace out as described. A few optional nits inline for whenever it is next refreshed, no need to re-spin for them.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 4981)

(minor) This isn't a bug, but the header parse fills `name` with a literal `%255s`, while the anchor parse a few lines down spells the same buffer's width as FIND_COOKIE_WIDTH(NAME_MAX) and its comment says the width is built from the buffer "so the two cannot drift apart". Only one of the two sscanf() calls on `name[NAME_MAX + 1]` has that property.

If the patch is refreshed, the header could use the macro too:

    "# lfs find --since-cookie for %" FIND_COOKIE_WIDTH(NAME_MAX) "s%n"

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5226)

(style) This isn't a bug, but the `if (sep == tmp)` arm has no braces while its `else if` arm does. Kernel style braces both when either needs them, if the patch is refreshed.

### 3. `Documentation/man1/lfs-find.1` (line 911)

(minor) "To accept the gap and go on, remove FILE" is the recovery for the purged-anchor refusal, but it sits four sentences after it, behind the race, the unreadable-object case and the advice to keep FILE off the searched filesystem. Read in place, "the gap" seems to refer to the cookie's own temporary writes.

If the patch is refreshed, could this sentence move up to follow "that is refused instead", so the refusal and the way out of it are read together?
