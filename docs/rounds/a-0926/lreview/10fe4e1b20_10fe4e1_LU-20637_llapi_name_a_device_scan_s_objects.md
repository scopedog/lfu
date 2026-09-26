# 10fe4e1b20 — LU-20637 llapi: name a device scan's objects

- **Commit:** `10fe4e1b2087` (10fe4e1b20, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 4.9M tokens, $3.05, 5m46s

## Overall assessment

Looks good; one minor inline comment on the public llapi_scan_rec_path() for whenever the patch is next refreshed -- no need to re-spin for it.

## Findings

### 1. `lustre/utils/liblustreapi_scan.c` (line 780)

(minor) Only CLS_OST_OBJ is kept away from the lookup here, but a public caller scanning with LLAPI_SCAN_F_INTERNAL also gets the OST's own objects. An O/<seq>/LAST_ID is CLS_INTERNAL, its [seq:0x0:0x0] passes fid_is_sane(), and so it falls through to the LLAPI_SCAN_FID arm:

    llapi_scan_rec_path()->llapi_fid2path_at()->__ll_fid2path()
      -> LU_SEQ_RANGE_OST -> obd_iocontrol(OBD_IOC_FID2PATH, dt_exp)

That asks the OST being scanned, which is out of service, so the call waits on it -- the case the comment above says would stop the scan on the first object. lfs is not exposed because find_decide() checks find_rec_may_have_name() first. The man page EXAMPLES, though, call this on every record a scan delivers. Would it be simpler to put that class check in here, so every record classified as something other than CLS_VISIBLE or CLS_OST_OBJ returns -ENOENT without a lookup?
