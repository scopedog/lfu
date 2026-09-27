# HEAD — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `62507e5a436b` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 9.8M tokens, $4.61, 8m21s

## Overall assessment

Mostly good; two minor points inline, fine to pick up on the next refresh. No need to re-spin for them alone.

## Findings

### 1. `lustre/utils/liblustreapi_scan_changelog.c` (line 85)

(minor) Should LLAPI_SCAN_BTIME be in this mask? scan_cl_mdt_stat() now asks statx() for STATX_BTIME, and scan_cl_resolve() copies it into lfsr_stx with STATX_BTIME set in stx_mask. The man page also says the birth time is filled where the MDT has one.

Because the bit is missing here, though:

- sc_want = LLAPI_SCAN_FID | LLAPI_SCAN_BTIME with _RESOLVE takes the early return in scan_cl_resolve(), since (sl_want & SCAN_CL_RESOLVE_MASK) == 0. No lookup runs, so no birth time comes back.
- sc_got never reports LLAPI_SCAN_BTIME, even for sc_want = 0 or LLAPI_SCAN_SIZE, where records do carry STATX_BTIME in stx_mask.

LLAPI_SCAN_WANT_KNOWN_DEV lists LLAPI_SCAN_BTIME for the device scanner.

### 2. `lustre/utils/liblustreapi_scan_changelog.c` (line 1152)

(minor) What happens when sc_type_mask and the user's registered mask have no bits in common? chlg_ioctl() in mdc stores the intersection as it is:

    crs->crs_user_mask = in.cf_mask & out.cf_mask;

and the record filter treats a zero crs_user_mask as "no filter":

    if (crs->crs_user_mask &&
        !(crs->crs_user_mask & BIT(rec->cr.cr_type)))

Take a user registered with `-m CREAT` (the man page recommends registering with a mask) and sc_type_mask = BIT(CL_UNLINK). The scan then delivers every record type in the log, which is the silent widening the commit message gives as the reason for refusing a mask without sc_user.

The root cause is in mdc, so it may belong in a separate patch. Until then, could llapi_scan_changelog.3 mention it under sc_type_mask?
