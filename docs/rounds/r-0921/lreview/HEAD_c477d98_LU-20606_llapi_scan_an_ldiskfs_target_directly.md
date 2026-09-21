# HEAD — LU-20606 llapi: scan an ldiskfs target directly

- **Commit:** `c477d98a7dd5` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **medium**
- **Run:** opus, 9.4M tokens, $8.41, 13m22s

## Overall assessment

Mostly good; one inline question about stx_blocks on an OST scan that looks worth a look before landing.

## Findings

### 1. `lustre/utils/liblustreapi_scan_device.c` (line 488)

(defect) Does this zero stx_blocks for every object on an OST scan?

An OST data object is S_ISREG and carries no trusted.lov, so it takes this branch, and the ternary then reports 0 blocks with STATX_BLOCKS set. The MDT reasoning in the comment above is right for an MDT inode -- mdt_pack_attr2body() does the same for a regular file with no layout -- but on an OST the object is the data, so so_blocks is the answer a consumer wants.

LLAPI_SCAN_BLOCKS also survives the OST narrowing: LLAPI_SCAN_WANT_MDT_ONLY does not name it, so lfsp_got promises blocks for an OST scan, and llapi_scan_device.3 says the same in prose -- "every data object on an OST -- where the object's size is exactly what that OST holds" -- followed by "The value is in lfsr_stx.stx_size and lfsr_stx.stx_blocks in every case". So the record claims a number it did not read rather than leaving the bit clear.

Would gating the zero on the target being an MDT work here, e.g. passing the scan_dev through and using obj->so_blocks when tt_flags has LLAPI_SCAN_TGT_OST?

conf-sanity 300 only checks that the OST arm exits 0, so nothing catches this today.
