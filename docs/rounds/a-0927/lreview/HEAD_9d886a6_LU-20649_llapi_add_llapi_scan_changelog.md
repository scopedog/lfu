# HEAD — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `9d886a62697c` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 4 finding(s), severity **medium**
- **Run:** opus, 6.1M tokens, $3.93, 8m33s

## Overall assessment

Mostly good, comments inline. The walk in scan_cl_clear() is worth fixing before this lands. The other comments are optional and can wait for the next refresh.

## Findings

### 1. `/COMMIT_MSG` (line 147)

(minor) Several paragraphs describe this change against its own earlier patchsets rather than against master:

- "the page said otherwise by listing all ten and then naming the flag"
- "The checkpoint gets its caveat, in the header and the page both."
- "sc_startrec and sc_endrec are both inclusive and the page now says so"
- "scan_cl_bucket() takes llapi_fid_hash() as it is ... a modulo on top could not change it"
- "It promised one record per object and left open which ..."
- "The man page said only that the mask is intersected with the user's own ..."

The page, the example and the modulo were never in the tree, so someone reading git log later has nothing to compare them against.

The body is also about 200 lines, and much of it repeats the code comments and llapi_scan_changelog.3 almost word for word. If the patch is refreshed, could the message be cut down to the purpose, the two modes, the clearing rule and the non-obvious design decisions?

### 2. `lustre/utils/liblustreapi_scan_changelog.c` (line 1002)

(defect) Can this still walk the whole cache on every record? It happens when a held object pins the clear point. The batch test above keeps passing, but the walk cannot move anything:

    an earlier clear stopped at L = held - 1 (B still cached, co_first = L + 1)
    other objects age out, so sl_accepted reaches L + 1000
    each later record: batch test passes -> scan_cl_held_first() -> upto = L -> return here

This continues until B leaves the cache. For a file that changes without pause, that can take 6 * sc_min_age of stream time, an hour by default. A continuously appended log file is enough to set it up.

Until then, with _COALESCE | _CLEAR, every record costs one pass over up to sc_max_cached (100000 by default) entries. A reader slowed down that much can fall behind the MDT it is meant to drain.

One fix: remember the sl_accepted value the last walk was made for, and walk again only after another SCAN_CL_CLEAR_BATCH records have been accepted. Another: keep the lowest co_first up to date as objects enter and leave the cache.

The comment above the batch test says the per-record walk is gone, but that only holds when nothing pins the clear point.

### 3. `lustre/utils/liblustreapi_scan_changelog.c` (line 1235)

(minor) With _FOLLOW and sc_type_mask both set, can the range fail to end? The mdc drops records whose type is not in the mask, and that includes record sc_endrec itself if it is the wrong type. The loop then never sees idx == sc_endrec.

It stops only when a matching record past sc_endrec arrives, which may never happen on a quiet filesystem. Until then, anything _COALESCE holds is not delivered.

If the combination is meant to be supported, a note here or in llapi_scan_changelog.3 would help. The note would say that the range ends only when a record at or past sc_endrec passes the mask.

### 4. `Documentation/man3/llapi_scan_changelog.3` (line 265)

(minor) "quiet is counted in records read and not in seconds passed" makes sc_min_age sound like a record count. It is still seconds, compared against the cr_time of the records read, so the clock only moves when a record arrives. If the patch is refreshed, maybe: "quiet is measured by the event times of the records read, so the clock stands still while no record arrives".
