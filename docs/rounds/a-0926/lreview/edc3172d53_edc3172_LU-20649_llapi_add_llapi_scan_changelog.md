# edc3172d53 — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `edc3172d5302` (edc3172d53, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 6.8M tokens, $3.90, 7m52s

## Overall assessment

Looks good. The coalescing cache, the clearing bound and the parameter copy-in all read correctly against the changelog reader and the MDS side. A few optional nits inline for whenever the patch is next refreshed; no need to re-spin for them.

## Findings

### 1. `/COMMIT_MSG` (line 196)

(minor) test6 is not the only case that needs -u: test9 needs it too, since sc_type_mask is refused without sc_user, and it skips without one ("no -u, so no user to filter for; skipped"). The sanity.sh comment above the llapi_scan_changelog_test call already says that. If the message is refreshed, something like "test6 and test9 need it and skip without one" would match the code.

### 2. `lustre/tests/llapi_scan_changelog_test.c` (line 20)

(minor) Following these instructions by hand makes test9 fail. A user registered with a plain changelog_register has a maskless CHANGELOG_USER_REC, so with -u test9's sc_type_mask goes through llapi_changelog_start_user() -> OBD_IOC_CHANGELOG_FILTER, the MDS lookup fails with -ENOENT (LU-20647), and the case reports "the masked scan failed". sanity 157d avoids this by registering with -m ALL, and llapi_scan_changelog.3 says the same.

If the patch is refreshed, the header could say "changelog_register -m ALL". usage() could also say that -u serves the filter case as well as the clear one, not just "for the cases that clear".

### 3. `lustre/tests/sanity.sh` (line 21284)

(style) This isn't a bug, but this precondition uses the negated `cond && skip` form. If the patch is refreshed, consider the positive form that test_160o uses:

    [[ $PARALLEL != "yes" ]] || skip "skip parallel run"
