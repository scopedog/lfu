# HEAD~1 — LU-20605 llapi: build find on the scan record

- **Commit:** `b5c561633172` (HEAD~1, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 5.6M tokens, $5.55, 10m14s

## Overall assessment

Looks good. The two-step gather reads well and the LMV predicates get their pre-stat rejection back. Only optional notes inline — nothing here needs a re-spin on its own.

## Findings

### 1. `/COMMIT_MSG` (line 41)

(minor) The bullet list covers six behaviour deltas, but not the new foreign-LMV arm in printf_format_lustre() case 'i'. That is user-visible too: `lfs find -printf '%Li'` on a foreign directory used to print lfm_type (whatever sat at the lum_stripe_offset offset) and now prints the directory's own MDT index, or nothing when it could not be fetched.

Worth a line alongside the others so a reader diffing the message against the diff isn't surprised by that hunk.

### 2. `lustre/utils/liblustreapi_pfind.c` (line 1819)

(minor) The new guard above settles case 'i' for a foreign LMV, but the siblings in this switch read the same buffer through lmv_user_md fields and lmv_foreign_md aliases all of them:

    lum_stripe_count  <-> lfm_length   (offset 4)
    lum_stripe_offset <-> lfm_type     (offset 8)
    lum_hash_type     <-> lfm_flags    (offset 12)

and lum_pool_name[]/lum_objects[] land inside lfm_value.

So %Lc prints lfm_length as a stripe count, %Lh decodes lfm_flags as a hash type, and %Lp runs snprintf("%s") over foreign bytes that need not hold a NUL.

This one looks like it can read out of bounds: str_cnt becomes lfm_length, and the loop indexes lum_objects[i] for that many entries. cb_get_dirstripe() only grows fp_lmv_md when the ioctl says E2BIG, so for a foreign value that fits the default 256-stripe buffer but has lfm_length above 256, objects[i] walks past the allocation — as far as the 1024-byte format buffer lets the loop run.

None of it is new in this patch, but since case 'i' is being taught about foreign LMVs here, should the others get the same treatment (or the whole directory branch bail out early on lmv_is_foreign())?

### 3. `lustre/utils/liblustreapi_pfind.c` (line 2768)

(style) This isn't a bug, but `have_lmv` is still in scope and scan_rec_mdt() sets LLAPI_SCAN_LMV from exactly that bool, so the two spellings of the same condition read as if they might differ.

find_foreign_accepts() above already takes the !gather_all case, which leaves this one reachable only when gather_all is set. If the patch is refreshed, `!have_lmv` here (and maybe a word about why gather_all lands here instead) would make the pairing obvious.
