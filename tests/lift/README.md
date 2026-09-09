# Lift-and-compare harnesses

A harness that retypes a function tests the copy, not the code. `lift.py`
cuts named functions out of the tree's real sources, comments and all, and
writes them to `lifted.inc`; the harness `#include`s that. Point it at a
second tree — a worktree, or a `git show HEAD:<file>` dump — and the same
harness runs the unfixed text, which is the only way an arm proves a fix
rather than restating it.

    python3 lift.py <tree> lifted.inc
    gcc -g -O0 -D_GNU_SOURCE -I<tree>/lustre/utils -I<tree>/include \
        -I<tree>/include/uapi -include <tree>/config.h \
        -o harness linkea_torn.c

## `linkea_torn.c` — 68159 `0aaa4e59`

Drives `find_device_prefilter()` over hand-built `trusted.link` buffers. A
torn linkea — `leh_reccount` claiming more names than the buffer spells —
used to make the object a **non-match** where the no-name case beside it
counts the same condition undecided.

**Unfixed 7 pass / 1 fail, fixed 8 / 0.**

The fixture is the fiddly part: `scan_linkea_entry()` caps `leh_reccount` by
the *smallest* entry that could fit, so a short first name caps `nr` to 1 and
the loop under test never runs. The buffer needs room for `claimed`
minimum-sized entries while the entries actually in it are long enough to run
off the end. The first three arms assert that premise before anything reads
into it.

## `lmv_stale.c` — 68156 `7e92da87`

Drives `scan_lmv_to_user()` over one buffer twice: a foreign directory with a
2048-byte value, then a 4-stripe directory. The shard area a consumer sizing
`lum_objects[]` by `lum_stripe_count` would read used to hold **96 of 96
bytes** of the foreign value.

    python3 lift_lmv.py <tree> lifted_lmv.inc

**Unfixed 3 pass / 1 fail, fixed 4 / 0.**

`lifted*.inc` is generated — regenerate it, do not commit it.

## `root_fid.c` — 68156 `4d552522`

Drives `scan_classify()` over four FIDs. The root with a non-zero `f_ver` used
to classify as namespace-visible, where `fid_is_root()` — a whole-struct
`lu_fid_eq()` — says it is not.

    python3 lift_root.py <tree> lifted_root.inc

**Unfixed 3 pass / 1 fail, fixed 4 / 0.**

Note `scan_classify()`'s second argument is `have_lma`: pass `true`, or every
arm answers `CLS_NO_LMA` and the harness reports the code broken.

## `at_mntfd.c` — llapi_scan_fid()'s move to `mnt_fd`

`llapi_scan_fid()` used to resolve the FID through `mnt_fd` and then read the
object through the composed absolute path, so the two arguments could name
different filesystems. Every syscall now goes through `mnt_fd` at the name
`fid2path` answered, which needs three cases the absolute form did not have:
the mount root itself (`fid2path` says `/`, which strips to nothing), an
object directly under the mount (its parent *is* `mnt_fd`), and the in-place
split that finds a nested object's parent without a second buffer.

The harness runs all three both ways over a plain directory tree and compares
`st_ino`, so it needs no Lustre:

        gcc -Wall -o at_mntfd at_mntfd.c
        mkdir -p /tmp/t/d/sub && touch /tmp/t/top /tmp/t/d/sub/f2
        ./at_mntfd /tmp/t

Six cases, all agreeing, including that `rel` survives the split unmodified.
