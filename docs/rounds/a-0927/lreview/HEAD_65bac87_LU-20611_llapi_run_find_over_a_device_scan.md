# HEAD — LU-20611 llapi: run find over a device scan

- **Commit:** `65bac8790e0d` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 7.2M tokens, $3.72, 7m58s

## Overall assessment

Looks good; two optional nits inline for whenever it is next refreshed -- no need to re-spin for them.

## Findings

### 1. `/COMMIT_MSG` (line 54)

(style) This isn't a bug, but this one is unaddressed from PS17. There, Andreas flagged these bullets (the per-magic minimum sizes, the swapped top-level foreign magic, the composite entry sizes) as reading like commentary on an older version of the patch and/or repeating earlier statements. The reply was "Fixed in the next PS", but the text is still here word for word.

The paragraph above already says that find_lmm_fits() bounds the layout before the swab. The per-magic details are also in the find_lmm_fits() comments. If the message is refreshed, could these bullets be trimmed to the user-visible effect?

### 2. `Documentation/man3/llapi_find_device.3` (line 148)

(minor) find_asks_layout() also counts --stripe-size and --extension-size as layout options, so over an OST they get -ENOTSUP as well. This list leaves both out. If the page is refreshed, could they be added so the documented refusals match the code?
