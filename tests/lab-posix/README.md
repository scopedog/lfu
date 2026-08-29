# Lab — the POSIX Input Scanner, and the FID a stat never answered for

The HLD's **POSIX Input Scanner** is the one client-side module still marked
*not started*. `architecture.md` §7 had already settled its shape — *the same
module with a different attribute source*, because `get_lmd_info_fd()` falls
back to `lstat` when the ioctl answers `ENOTTY` — so the first question was not
"how do we build it" but **"what does the scanner already do off Lustre, and is
it honest?"**

`probe.c` asks that directly: it calls `llapi_scan_namespace()` on a tree that
is not Lustre and prints each record's `sr_valid`.

## What the probe found (2026-08-29)

It works — and it lies about one field.

```
/tmp/ptree/a       mode=100644 size=0  fid=[0x61:0x0:0x0]
    valid=0x43ff [FID,TYPE,MODE,NLINK,UID,GID,SIZE,BLOCKS,ATIME,MTIME,CTIME]
/tmp/ptree/big     mode=100644 size=6  fid=[0x676962:0x0:0x0]
    valid=0x43ff [FID,TYPE,MODE,NLINK,UID,GID,SIZE,BLOCKS,ATIME,MTIME,CTIME]

llapi_scan_namespace(/tmp/ptree) = 0 (ok), 7 objects
```

**`0x61` is `'a'`. `0x676962` is `"big"`.** The FID is the object's own
filename, and `LLAPI_SCAN_FID` is *set*, so a consumer doing exactly what the
validity mask tells it reads a fabricated FID.

The mechanism, in three steps:

1. the walk writes the object's **name** into `param->fp_lmd` — that buffer is
   the ioctl's input as well as its output;
2. the ioctl answers `ENOTTY` (not Lustre), so `get_lmd_info_fd()` falls back to
   `lstat` and calls `convert_lmd_statx()`, which fills `lmd_stx` **and never
   touches `lmd_fid`**;
3. `scan_rec_mdt()` copies `lmd_fid` into `sr_fid` and sets the bit if
   `fid_is_sane()` — and a small seq with no version reads as a valid **IGIF**,
   so the name passes.

`lfs find` never noticed because it does not read `lmd_fid`: `-printf %F` calls
`llapi_path2fid()` on the path instead. The scanner API is the first consumer of
that field, which is why this is ours to fix rather than a bug report.

**The sibling case was already fixed in the same change.**
`convert_lmdbuf_v1v2()` carries `/* V1 put lmd_st where lmd_fid is: those bytes
are not a FID */` and a `memset`. Same defect, same function one caller away,
found then and missed here. The fix moves the clear **into
`convert_lmd_statx()`**, so both callers get it and the V1 memset goes.

## The arms

| arm | what is cut | `llapi_scan_test -t 10` |
|---|---|---|
| `post` | the tree as committed | **pass** |
| `nofid` | the `lmd_fid` clear cut out | **fail** — `a record off Lustre carried a FID: valid=0x43ff` |

```sh
scp cut-fid.py 01-arms.sh nishida@192.168.122.10:~/
ssh nishida@192.168.122.10 'ARM=nofid LTREE=~/lustre-160ac bash 01-arms.sh'
ssh nishida@192.168.122.10 'cd ~/lustre-160ac/lustre/tests &&
    ./llapi_scan_test -d /mnt/lustre/d157c -p /tmp -t 10'
```

`01-arms.sh` rebuilds `lustre/utils` **and** `lustre/tests`: the test binary
links `liblustreapi`, so rebuilding the library alone can leave the old code in
the binary — the trap `lab-scanstats/README.md` records.

## The contract this settles

Measured, not assumed — the second probe run demanded every field
(`sp_want = ~0`):

| off Lustre | bits |
|---|---|
| **answered** | `TYPE MODE NLINK UID GID SIZE BLOCKS ATIME MTIME CTIME`, and `PROJID` where the filesystem has project quotas (ext4 answers `FS_IOC_FSGETXATTR`) |
| **absent, correctly** | `LAYOUT LMV MDT_INDEX HSM` — nothing off Lustre has them |
| **absent, only after the fix** | `FID` |
| **absent, and could be answered** | `BTIME`, `ATTRS` — the fallback uses `lstat`, which has neither. `statx()` would give both. Not done here |

`llapi_scan_test`'s **test10** asserts all four rows. It **refuses to run on
Lustre** rather than pass there: every absence it checks would be present for a
good reason, so a green run on Lustre would mean nothing. Give `-p DIR` when
`P_tmpdir` is Lustre.

## `statx()` instead of `lstat` — checked, and not necessary

Measured on the lab: `lfs find /tmp/ptree -type f -btime -1d` returns **nothing**
for files created seconds earlier, where the same command on Lustre returns the
file. That looks like a POSIX gap and is not one — `find_decide()` treats an
object with no `STATX_BTIME` as not matching, deliberately, and **an old ldiskfs
inode whose `i_extra_isize` does not reach `i_crtime` behaves the same way on
Lustre**. `statx()` would fix one half of that and leave the other.

The HLD names `statx()` for this module but does not require it: the module sits
outside the three initial Input Scanners, `btime` is not in its standard
attribute list, and it explicitly allows returning attributes only *"if readily
available"*. See [`design-posix-scanner.md`](../../docs/design-posix-scanner.md)
§4. An enhancement worth its own patch, not a correctness fix.
