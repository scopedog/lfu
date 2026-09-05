# lreview on 68417 — three findings, all real, and one fix that broke `--since`

**3 findings, severity medium** — the highest of the run so far —
**14.8M tokens, $11.68.** All three verified against the tree; none
already fixed.

## `(1)` — one unreadable object ended the whole search

`find_since_cand_cb()` ended `return rc`.  `llapi_scan_changelog()`
returns a callback's value **unchanged**, and the loop over the MDTs
breaks on it, so a single per-object failure abandoned the run — this
MDT and every one behind it.

A walk does not do that: `llapi_semantic_traverse()` records the error
and reads the next dirent unless `fp_stop_on_error` is set.  `--since`
asks the same question of the same objects and now answers it the same
way: keep the first error, carry on, return it at the end.

The way in is ordinary.  With `llite.*.user_fid2path` set so a non-root
caller can resolve FIDs at all, `llapi_scan_fid()` `statx()`es the
resolved pathname **before it opens anything** — so the first changed
object under a `0700` directory owned by someone else answers `-EACCES`.
That is neither `-ENOENT` nor `-ESTALE`, so it was not counted as gone
either: the run simply stopped, having examined none of the candidates
after it.

### Where the fold goes matters

68419 holds the cookie back when a resolve failure dropped matches, so
the next run does not skip their records for good.  A per-object failure
**is** dropped matches, so `fss_scan_rc` folds into `rc` *before* the
rewrite, beside `fss_path_rc` and for the same reason.  Getting that
order wrong would have advanced the anchor past objects this run never
reported.

## `(2)` — encrypted files lost every alternate name

`mdt_path_current()` ends

    if (isenc != 1)
            ptr++; /* skip leading / unless this is an encrypted file */

so `fid2path` answers `"/a/f"` for a file carrying `LUSTRE_ENCRYPT_FL`
where every other object answers `"a/f"`.  The hardlink loop composed
that unstripped, giving `"<mnt>//a/f"`, which `find_since_under()` fails
on its `strncmp` against any root **below the mount** — so the alternate
names this loop exists to find were dropped for exactly the files that
need them.

`llapi_scan_fid()` and `llapi_scan_rec_path()` both strip leading slashes
before composing, and one carries a comment saying why ("Composing that
with the mount would name it `<mnt>//`").  This is now the third
composer doing the same thing.

Verified in the kernel tree: `lustre/mdt/mdt_handler.c:7893`.

## `(3)` — and the fix for it broke `--since` outright

`--threads` was parsed, accepted and silently ignored on this path, the
mismatch `find_device_supported()` refuses it for.  So I refused it here
too — and **`lfs find --since 2h` then failed with `-ENOTSUP` for every
run**, because `lfs_find()` computes a default thread count *before*
dispatching:

    if (param.fp_thread_count == 0)
            param.fp_thread_count = calculate_default_thread_count(...);

so `fp_thread_count > 1` was true whether or not the user said
`--threads`.  The reviewer's own text said "lfs_find() always sets it
before dispatching"; I read that and still put the check where the
default had already run.

**Caught on the lab, not in review** — `--since 2h` alone returned 95.
The default is now set on the walk's arm of the dispatch, where it is
the only arm that uses it, so it tracks the branch condition as 68418
and 68419 extend it rather than being a second copy that can drift.

    --since 2h                 exit 0    (was 95 with the first fix)
    --threads 8 --since 2h     exit 95, "--threads describes a walk; ..."
    --threads 4 -type d        exit 0
    -type d                    exit 0    (default still applied)

## And one process note

While installing for that test I ran `cp lfs /usr/bin/lfs` from the
build directory — which copies the **libtool wrapper**, not the binary,
and the test then ran `lt-lfs` against the build tree.  That is the trap
recorded in [[lfu-lreview]] from the cookie work, hit again.  `.libs/lfs`
is the binary.  The first `--threads` result was read off that wrapper
and had to be discarded.

## Lab

ldiskfs, MDSCOUNT=2 OSTCOUNT=2: **56El, 160aa, 160ab, 160ac, 160ad pass;
`llapi_scan_test` 11 of 11.**  checkpatch: 0 errors on all three touched
commits, 68417's two warnings the standing false positives.  18 changes,
18 Change-Ids.

The fixes touch 68417 and were carried by hand through 68418 and 68419,
which both rewrite the dispatch and the entry validation.
