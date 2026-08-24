# Upstream bug: cb_get_dirstripe() reopen leaves the caller's descriptor stale

**Filed 2026-08-22 as LU-20624** — Bug, standalone, **not under LU-20462** — this is stock Lustre, found while building the LFU scanner on
top of `liblustreapi_pfind.c`.

**Why standalone** (decided 2026-08-22): LU-20462's scope is the Lustre Find
Utility, and this breaks `lfs find`, `lfs getstripe` and `lfs getdirstripe`,
three client commands with nothing to do with it. Someone whose `lfs getstripe
-r` skipped a subtree will never look inside an LFU epic. It affects 2.14.51
onward, so b2_15 and b2_16 are backport candidates and it must be schedulable
apart from an unlanded 2.19 feature. Link it *Related to* LU-20603 and LU-20605
and name LU-20462 in the description as where it was found; do not parent it.

**Neither LU-12104 nor LU-18067 is this.** LU-12104 was a SEGV under the same
predicates, fixed in 2.13.0, before the reopen existed. LU-18067 is the commit
that added the FIFO guard *inside* this retry block (fixed 2.16.0) and did not
notice the descriptor. Both are worth citing.

**Found 2026-08-22**, chasing a failure in `tests/lab-scan/15-nonlustre.sh`.
Reproduced on **unpatched master at `5afbab284e`** on `lfu-r4-ldiskfs`, with
strace. Our own fix for it is in the LFU series (LU-20603 and LU-20605), which
is why this ticket should exist: a reviewer seeing that hunk needs somewhere to
look, and the `lfs getstripe` half is not ours to carry.

## Suggested fields

| Field | Value |
|---|---|
| Type | Bug |
| Severity/Priority | Major — silent data-skip plus a descriptor-reuse hazard |
| Affects Version | 2.14.51 and every release since |
| Component | (the LU project defines none) |

Origin: the reopen came in with `15d44e787e` **LU-12682 llite: fake symlink type
of foreign file/dir** (2019-08-22), first tagged 2.14.51. The code later moved
to `liblustreapi_pfind.c` in `48a82603b8` LU-19052 without changing shape.

## Summary line

```
utils: cb_get_dirstripe() reopen leaves the caller's directory fd stale
```

## Description (paste as-is)

Prose below has no hyphen pair, asterisk or brace outside a `{code}` block, so
Jira's editor has nothing to autoformat. See the note in
[`lfind.md`](lfind.md) about what happens otherwise.

---

```
llapi_semantic_traverse() hands a directory descriptor to its sem_init
callback by pointer, then calls fdopendir() on its own copy.
cb_get_dirstripe() closes that descriptor and stores an O_NOFOLLOW reopen
through the pointer when LL_IOC_LMV_GETSTRIPE answers ENOTTY, which it does
for the fake symlink a foreign file or directory presents and for any
directory not on Lustre at all.

Two callers pass the address of a local copy, so the traversal keeps the
number that was closed:

{code}
lustre/utils/liblustreapi_pfind.c:2423   int d = dp == NULL ? -1 : *dp;
lustre/utils/liblustreapi_pfind.c:2510       ret = cb_get_dirstripe(path, &d, param);

lustre/utils/liblustreapi.c:3551         int d = dp == NULL ? -1 : *dp, fd = -1;
lustre/utils/liblustreapi.c:3569             ret = cb_get_dirstripe(path, &d, param);
{code}

It then descends on a closed descriptor, so every object below that
directory is skipped in silence; closes that number a second time on the way
out, by which point the walk may have reissued it to another thread; and
leaks the descriptor that was opened.

Reproduced on master at 5afbab284e with a tmpfs mounted inside a Lustre
mount point, holding a.txt and sub/b.txt:

{code}
# no predicate, so cb_get_dirstripe() is never called: correct
$ lfs find /mnt/testfs/nl
/mnt/testfs/nl
/mnt/testfs/nl/a.txt
/mnt/testfs/nl/sub
/mnt/testfs/nl/sub/b.txt

# any predicate needing the directory stripe: the subtree is gone
$ lfs find /mnt/testfs/nl --printf '%p\n'
lt-lfs: failed for '/mnt/testfs/nl': Operation not permitted
$ echo $?
1
{code}

Each of these reproduces identically:

{code}
--printf        --links        --mdt-count        --mdt-hash        --foreign
{code}

The errno is wrong too: cb_get_dirstripe() returns the ioctl's -1 rather
than a negative errno and cb_find_init() passes it out unchanged, so ENOTTY
is reported as "Operation not permitted".

lfs getdirstripe and lfs getstripe -D reach the same call through
cb_getstripe(), but stop at the ENOTTY in any case, so there it is the
double close that matters rather than a lost walk. Plain lfs getstripe -r
sets neither fp_get_lmv nor fp_get_default_lmv and does not reach it.

That makes lfs getdirstripe -r the clearest view of the descriptor, the two
runs being identical until the final close (strace of the main process):

{code}
  openat(AT_FDCWD, "/mnt/testfs/nl2", O_RDONLY|O_NONBLOCK|O_DIRECTORY) = 3
  openat(AT_FDCWD, "/mnt/testfs/nl2", O_RDONLY|O_NONBLOCK|O_NOFOLLOW)  = 4
  close(3)                                = 0
  openat(AT_FDCWD, "/mnt/testfs/nl2", O_RDONLY|O_NONBLOCK|O_NOFOLLOW)  = 3
  close(4)                                = 0
  close(4)                                = -1 EBADF   <- without the fix
  close(3)                                = 0          <- with it
{code}

3 is the traversal's descriptor and 4 the reopen. The third line is
cb_get_dirstripe() closing the original, and the openat after it takes 3
straight back while the caller still believes it owns that number.

The fix is to write the descriptor back in both callers:

{code:c}
        ret = cb_get_dirstripe(path, &d, param);
        if (dp != NULL)
                *dp = d;
{code}

The third caller, in the dangling-symlink arm of cb_getstripe(), opens a
descriptor it closes itself and is correct as it stands.
```

---

## Notes for us, not for the ticket

**Why we hit it and upstream mostly has not.** The condition above is
predicate-driven, so a plain `lfs find` never calls `cb_get_dirstripe()`. Our
`llapi_scan_namespace()` asks for `LLAPI_SCAN_LMV` on **every** directory in its
default demand mask, so what is an upstream corner case would have been our
common case — every non-Lustre directory below the mount, losing its whole
subtree, on the code path the scanner's consumers act on.

**The AI review found the symptom, not this.** Its comment on
`liblustreapi_scan.c:303` correctly said `rec->sr_fd` was left holding the
pre-reopen descriptor. Fixing that made the *record* right; the traversal's own
copy was still stale, which is what actually lost the subtree. Worth remembering
as a case where taking a review comment at face value fixes less than it looks.

**The fix is its own change at the bottom of the LFU stack**, carrying this
ticket rather than LU-20603/LU-20605, so it is landable and backportable on its
own and a reviewer of the scanner patches does not meet an unexplained fd hunk.
It fixes both pre-existing callers, `cb_find_init()` and `cb_getstripe()`.
`llapi_scan_cb_init()` is new code in LU-20603 and is simply written correctly
there, with its message pointing here.

Local commit `acf59cca21`, 12 lines, subject:

```
LU-20624 utils: stale dir fd after dirstripe reopen
```

The placeholder is gone: `LU-20624` is in the subject and in the one reference
each in LU-20603's and LU-20605's messages, verified with no `LU-20624` left in
the series.

**Evidence:** `bench-data/2026-08-22/upstream-stale-fd-repro.txt`, and
`tests/lab-scan/15-nonlustre.sh`, which fails on unpatched master and passes
with the series.

**One claim corrected after measuring.** The first draft said `lfs getstripe`
and `lfs getdirstripe` "lose the subtree in the same way", and cited seven
EBADF closes in one `lfs find`. Both were wrong. The getstripe pair stop at
the ENOTTY regardless, so the descriptor costs them the double close and not
the walk; and the seven-EBADF count came from `strace -f`, which was counting
other processes — the main process shows none for `lfs find`, because there
the stale number has already been reissued and the close silently succeeds.
The lab run that was meant to confirm the getstripe half is what caught it.
