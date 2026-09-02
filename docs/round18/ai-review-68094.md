# Round 18: the AI review on 68094 PS15

Five comments, all on `LU-20603 llapi: namespace scanner API`, arrived
2026-09-02 04:23.  Verified against `r16-work` before acting on any of them.

| # | Where | Verdict | Fix |
|---|---|---|---|
| 1 | `llapi_scan_namespace.3:129` | valid | the page said to hand `sr_lmm` straight to `llapi_layout_get_by_xattr(3)`, which takes a non-const buffer and byte-swaps it in place.  `sr_lmm` is `const struct lov_user_md *` and points into the scan's own reused buffer.  The page now says to copy `sr_lmmsize` bytes first, which is what `layout_cb()` in `llapi_scan_test.c` already did |
| 2 | `llapi_scan_namespace.3:348` | valid | `Documentation/man7/lustreapi.7` listed none of the five new `llapi_scan_*(3)` pages.  A `Namespace Scanning` subsection is added in 68094 and each later change appends its own page, so the index is never ahead of the pages |
| 3 | `lustreapi.h:624` | valid | `sr_atime`/`sr_mtime`/`sr_ctime`/`sr_btime` carried no unit while `sr_blocks` two lines up documents its own.  They are whole seconds: a scanner keeps only `stx_*time.tv_sec`, so an incremental scan keyed off `sr_mtime` has no sub-second precision to key on.  Said so |
| 4 | `lustreapi.h:707` | half | the dead `fp_min_depth` test in `llapi_scan_cb_init()` is real — `param` is `{ 0 }` and nothing ever sets it — and is removed.  But the premise is wrong: `lfs find` does not go through `llapi_scan_namespace()`, it uses `liblustreapi_pfind.c` with `find_param` directly, so `-D 0` and `-d N` are untouched by this API.  No `sp_min_depth` added; `sp_max_depth` is documented instead, in `find(1)`'s counting |
| 5 | `liblustreapi_scan.c:461` | declined | the `HAS_STDATOMIC` shim exists because C11 `<stdatomic.h>` and `atomic_int` may be absent, not because the `__atomic_*` builtins may be.  Every compiler the tree supports has them, and `liblustreapi_scan_device.c` uses them throughout |

## Verification

`groff -mandoc -ww` clean on both pages; `checkpatch.pl` on each of the five
touched commits shows only the pre-existing `.TH` line-length CHECKs, none on a
line this round added; `make` in `lustre/utils` clean under `-Werror`.

Comment 4's removal changes no behaviour: `fp_depth` is unsigned and
`fp_min_depth` is always 0, so the test could never be true.
