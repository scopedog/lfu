# HEAD — LU-20650 lfs: find --since-cookie, check each MDT when read

- **Commit:** `378786d5f308` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 6 finding(s), severity **low**
- **Run:** opus, 1.1M tokens, $1.16, 2m10s

## Overall assessment

The re-check itself looks correct, and it stops the cookie being rewritten as intended. One documentation claim does not hold, though: after this refusal the next run is refused too, it does not print the matches again. That should be fixed in the comment, the man page and the commit message on the next refresh. The remaining notes are minor.

## Findings

### 1. `/COMMIT_MSG` (line 19)

(minor) Does the next run really print them again? The purge that caused this -ESTALE leaves the log's oldest record past anchor + 1, and the anchor was not rewritten. So the next run's find_cookie_check() hits the same `oldest > anchor + 1` test and refuses before printing anything. That stays true until FILE is removed, or the log empties (the blind spot already documented). The cookie not being rewritten is right, but the reason given here is not what happens.

### 2. `/COMMIT_MSG` (line 26)

(minor) Another case is not covered and is not listed here: a purge on the MDT that is being read right now. That covers a purge that lands between this check and llapi_changelog_start(), or one that overtakes the reader during a scan slowed by per-object lookups. Should it be listed with the empty-log and late-record cases? On a single-MDT filesystem this is the only window there is.

### 3. `lustre/utils/liblustreapi_pfind.c` (line 6508)

(minor) Same point as the commit message. With the anchor left in place, the next run is refused by find_cookie_check(), which still sees oldest > anchor + 1. It does not repeat the matches. Recovery is removing the cookie, which restarts every MDT at its oldest record. Could the comment say that instead?

### 4. `lustre/utils/liblustreapi_pfind.c` (line 6511)

(suggestion) For i == 0 this repeats the read find_cookie_check() made just before the loop, with no scan in between. So on a single-MDT filesystem the patch adds an extra changelog open and nothing else. If the patch is refreshed, consider gating it on `i > 0`, which is the case the comment above describes ("while an earlier one was being read").

### 5. `Documentation/man1/lfs-find.1` (line 787)

(minor) After this refusal the next run is refused too: the anchor is unchanged and the purge has passed it, so the stale check fails again. Something like "FILE is not rewritten; the next run is refused the same way until FILE is removed" would match the code and point at the recovery described a few lines down.

Also, "Every MDT is checked ... and again just before it is read" follows the description of both the purge and the restarted-log refusals, but only the purge test is repeated. A purge on the MDT that is currently being read is still not caught either. The "What is not caught" sentence could name that too.

### 6. `Documentation/man3/llapi_find_since.3` (line 220)

(minor) Only the purged-past test is repeated here, not the restarted-log test from the sentence before. It might be worth saying so, and also that a clear on the MDT being read is still not seen.
