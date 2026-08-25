# LU-20643 — a reused lmd buffer is read as this object's attributes

**Status:** filed as LU-20643 on 2026-08-25. The fix is one commit on branch
`stale-lmd-buffer` in `~/projects/lustre/lustre-lu20603`, rebased onto the
series base (`5afbab284e`) so it stands alone rather than behind LU-20624.
Not pushed yet.

**Jira:** [LU-20643](https://jira.whamcloud.com/browse/LU-20643) ·
**Type:** Bug · **Component:** none (the LU project defines none) ·
**Affects:** master, and every release with `liblustreapi_pfind.c`

---

## Summary (as filed)

```
lfs find can answer -btime and -attrs from a stale buffer
```

## Description (paste as-is; the code block keeps its bytes)

`get_lmd_info_fd()` fills one `struct lov_user_mds_data` per traversal and
reuses it for every object. `convert_lmd_statx()` writes only the fields
`lstat(2)` supplies, so the rest of `lmd_stx` keeps whatever the previous
object left there.

Two paths make that visible.

On the V1 ioctl path, `lmd_st` covers `lmd_stx`, and only some statx fields
are written over it:

```
	stx_attributes_mask (lmd+72) <- st_atim.tv_sec
	stx_attributes      (lmd+24) <- st_mode | st_uid << 32
	stx_mask            (lmd+16) <- st_nlink, then |= STATX_BASIC_STATS
```

`st_atim.tv_sec` is never 0 in practice, so `stx_attributes_mask` comes back
non-zero for every object, and a directory whose link count has bit 0x800 set
turns on `STATX_BTIME` the same way.

On the `lstat` fallback, the buffer still holds the file name that was written
into it for the ioctl. Those bytes sit in `lmd_fid`, where a short name lands
in the IGIF range and `fid_is_sane()` accepts it:

```
	"readme.txt"               -> [0x742e656d64616572:0x7478:0x0], sane
	"my-backup-file-01.tar.gz" -> STATX_BTIME set in stx_mask
```

So a walk that crosses onto a subtree that is not Lustre can answer `-btime`
and the attribute predicates from a file name, and report a FID made of one.

## The fix

Clear what is about to be reused on both paths, and leave the glimpse path
alone, where the MDT's answer is still wanted.

## How it was found

Reading `liblustreapi_pfind.c` while building the LU-20462 scanner API, whose
record exposes the same fields through `LLAPI_SCAN_ATTRS` and
`LLAPI_SCAN_FID`. Same shape as LU-20624: a pre-existing defect found while
building on top of this code, filed and pushed separately rather than folded
into the series.
