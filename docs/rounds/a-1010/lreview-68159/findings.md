# HEAD — LU-20611 llapi: run find over a device scan

- **Commit:** `1abfebbd8c15` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 5 finding(s), severity **low**
- **Run:** opus, 8.6M tokens, $5.15, 10m55s

## Overall assessment

Mostly good. No defect found in this revision; the layout bounding, the linkea walk and the --ost/--mdt handling all trace correctly. A few optional minors inline for whenever it is next refreshed -- no need to re-spin for them.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 4250)

(minor) With fp_get_lmv set here, an unstriped directory under `! --foreign` takes the first test in find_decide():

    if (param->fp_get_lmv && param->fp_check_foreign &&
        param->fp_exclude_foreign &&
        !(fc->fc_rec->lfsr_valid & LLAPI_SCAN_LMV))
            goto print;

so every predicate after it is skipped. For example `! --foreign --uid 500` or `! --foreign --size +1G` over an MDT prints every unstriped directory, whatever its owner or size, and nothing is counted undecided.

The note above find_foreign_accepts() describes this for a walk, where the shortcut saves the getattr. A scan already has the whole record, so it gains nothing from it. Could a scan skip the shortcut (path == NULL)? Otherwise, could llapi_find_device.3 say that `! --foreign` is not combined with the other predicates for a directory?

### 2. `lustre/utils/liblustreapi_pfind.c` (line 4245)

(minor) Not from this patch, but it decides what --foreign answers here for a directory. The S_ISDIR arm of find_check_foreign() looks inverted since baba1fd07a ("LU-14489 utils: fix 'lfs find --mdt-count'"), which turned

    if (lfm->lfm_magic != LMV_MAGIC_FOREIGN) {

into

    if (lmv_is_foreign(lfm->lfm_magic)) {

As it reads now, `--foreign` rejects a foreign directory and accepts a striped directory that is not foreign. With a type given, it compares lum_stripe_offset as lfm_type. An unstriped directory never reaches it, because of the have_lmv tests before it.

So the large foreign LMV that find_rec_to_lmv() grows the buffer for is then rejected by --foreign, on a scan and on a walk alike. Is that reading right? If so it is a separate fix with its own Fixes: line. No test in lustre/tests runs `lfs find --foreign` today.

### 3. `lustre/utils/liblustreapi_pfind.c` (line 4332)

(minor) llapi_find_with_cb() runs validate_printf_str() before a walk, which warns about an unknown directive or a trailing '%'. This entry point does not, so `-printf '%Q'` over a target prints the text as it stands with no warning. If the patch is refreshed, could it be called here, next to the %p check?

### 4. `lustre/utils/liblustreapi_pfind.c` (line 3902)

(minor) Is "the no-layout path" still what happens? When find_lmm_fits() refuses the bytes, find_rec_to_lmd() returns true, and find_rec_layout() then counts the object undecided for the layout options. It does not forge the default, and the note above find_rec_layout() says so. If the patch is refreshed, could this comment say "undecided"?

### 5. `Documentation/man3/llapi_find_device.3` (line 81)

(style) This isn't a bug, but the option names and negative errnos on this page are written with a bare `-` (`-atime`, `--ost`, `-EINVAL`). troff sets that as a hyphen and may break a line at it. If the patch is refreshed, consider `\-` for these, as man-pages(7) asks.
