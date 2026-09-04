# `sanity 56El` — found, fixed, and proved against the unfixed build

Open since this session's first tick.  **lreview on 68095 found it**, on
the change that introduced it.

## What it was

`-printf` sets `gather_all`, which sends **every** object through the
project-id fetch.  68095 made the walk descend into a subtree that is not
on Lustre, so that fetch now runs on objects off Lustre -- and it is the
*third* such fetch, beside the two that patch already quiets (`%LF`'s
`llapi_path2fid()` and `%Lc`'s layout).  It was left as an error:

    ret = find_get_projid(fc, lmd->lmd_stx.stx_mode, &projid);
    if (ret) {
            llapi_error(... "failed to get project id from file ...");
            return ret;                     /* -> lfs find exits non-zero */
    }

`get_projid()` has two arms and **both** answer `ENOTTY` off Lustre:

| object | fetch | off Lustre |
|---|---|---|
| symlink, device node | `ioctl(parent, LL_IOC_PROJECT)` | **always** -- it is Lustre's own ioctl number |
| regular file, directory | `ioctl(fd, FS_IOC_FSGETXATTR)` | on a client **older than Linux v6.0**; tmpfs grew `shmem_fileattr_get` then |

## Why CI failed and the lab did not

CI is **rocky8.10, kernel 4.18** -- no `fileattr` on tmpfs, so the first
*regular file* under the subtree failed.  The lab is **rhel9.7, kernel
5.14**, which has it, so every object answered and the test passed.  That
is the whole difference, and it is why the failure was backend- and
DNE-independent: 68095 and everything above it, ldiskfs and ZFS alike.

Earlier ticks ruled out DNE, striping and the backend by experiment and
were left pointing at "rocky8.10 vs rhel9.7" without knowing *what* about
it.  This is what.

## Reproduced locally after all

The symlink arm needs no old kernel.  Adding one to the fixture
reproduces it on rhel9.7:

    lfs find $D -printf '%LF %Lc %p\n'
    exit=25
    lfs find: warning: get_projid: failed to get xattr for '.../l1': Inappropriate ioctl for device
    lfs find: warning: find_decide: failed to get project id from file ".../l1"
    lfs: failed for '/mnt/lustre/d56repro': Inappropriate ioctl for device

## The fix

`ENOTTY` is an answer, not a failure -- the convention 68095 already
established for the FID and the layout:

- `get_projid()` stops printing a warning for it;
- the caller treats it as "no project id": a search that **asked** for one
  cannot be answered for such an object, so it does not match; one that
  only **prints** it prints `DEFAULT_PROJID`.

Landed in **68095**, where the reachability was introduced.  68157 moves
that block into `find_decide()` and 68159 adds the `-ENOTSUP`/device-scan
arm beside it, so the fix was carried through both rebases by hand; the
two arms are disjoint and both are kept.

## Proved against the unfixed build, not just asserted

Same `lfs`, same test, `liblustreapi.so` swapped -- the discriminator is
the library, as it was for the cookie work:

| library | exit | stderr |
|---|---|---|
| unfixed | **25** | 347 bytes |
| fixed | **0** | 0 bytes |

And the strengthened test itself, against the unfixed library:

    sanity test_56El: @@@@@@ FAIL: lfs find -printf %LP failed on ...
    FAIL 56El

So the test catches the bug it is named for, rather than passing either
way.  (This is the control I failed to run on the `sp_size` change
earlier tonight, which is how that one got as far as it did.)

## The test grew what it was missing

lreview's second finding: the fixture was regular files and directories
only, so it never touched the arm that fails on **every** kernel.  Now it
has a symlink, and a `%LP` assertion so the project-id path is exercised
by name rather than incidentally:

    ln -s f1 $tmp/l1
    $LFS find $dir -printf '%LP %p\n' ...   # exit 0, stderr empty

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2: **56El, 160aa, 160ab, 160ac, 160ad all
PASS.**  checkpatch 0 errors on all three touched commits.  18 changes,
18 Change-Ids.

Still to confirm on rocky8.10, which only CI has -- but the regular-file
arm is the same `ENOTTY` through the same line, so the next round's
result is the check.
