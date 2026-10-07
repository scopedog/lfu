# bc5e232bd9 — LU-20650 lfs: find --since, warn when the log was cleared

- **Commit:** `bc5e232bd9d5` (bc5e232bd9, local review — not tied to a Gerrit change)
- **Review:** 4 finding(s), severity **low**
- **Run:** opus, 1.5M tokens, $1.35, 2m35s

## Overall assessment

Mostly good, minor comments inline. The main point is that the time-anchor warning states a loss that the check cannot actually establish; the rest are optional nits for whenever the patch is next refreshed.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 5214)

(minor) For a time anchor this only shows that the oldest remaining record is newer than the anchor. It does not show that anything at or after the anchor was cleared. The cleared records can all be older than the window.

Example: a policy engine has cleared every record up to N, all from yesterday. The filesystem is idle overnight. At 08:55 a file is created (record N+1). At 09:00 `lfs find --since 1h` gets oldest = N+1 > 1 and when = 08:55 > 08:00, so it prints "has been cleared past the --since anchor ... changes before it are not in the answer", but nothing in the window was lost. On the sites the commit message describes (a policy engine consuming the log), this will fire on nearly every run.

A client can't see the time of the last cleared record, so the check probably can't be made exact. Could the message say only what is known, e.g. "'%s' starts at record %llu from %s, after the --since anchor; anything cleared before it is not in the answer"? The index case is exact and could keep the stronger wording. sanity 160Af greps for the current text, so it would need the same change.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 5210)

(minor) find_since_gap() is called for every MDT in llapi_find_since(), including `lfs find --changelog all` with no --since (fp_since_kind == LLAPI_SINCE_NONE) and `--since 0`. In both cases find_cl_first() opens and reads each MDT's changelog, and then the `gap` test throws the result away. If the patch is refreshed, consider deciding on fp_since_kind / fp_since_index first and reading the log only when there is an anchor to compare against.

### 3. `lustre/utils/liblustreapi_pfind.c` (line 5145)

(style) This isn't a bug, but the new struct sits between find_cl_first_cb()'s comment ("Stop at the first record ...") and the callback, so the comment now appears to describe the struct. Also, find_cl_first()'s comment doesn't mention @first_time and still describes only the cookie use. If the patch is refreshed, consider moving the struct above the comment and adding a line on @first_time.

### 4. `/COMMIT_MSG` (line 16)

(style) "as 69443 does for the cookie" refers to a Gerrit change number, which `git log` readers can't follow. Could this name the commit by subject and the function instead (find_cookie_check(), via find_cl_first())? Naming find_since_gap() in the body would also make the change easier to find later.
