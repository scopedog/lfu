# lreview on 68160 — one finding fixed, and a coverage gap now made concrete

**1 finding, severity low, 5.6M tokens, $5.77.**

## The finding: a comment that promised a refusal it does not get

`lfind.c` said its own options are "spelled in full ... the abbreviations
and the single-dash forms `getopt_long_only()` would allow are not read
here, and **reach the predicate parser as unknown options**."

That holds for `-local` and `-internal`.  It does not hold for
`-device`: `getopt_long_only()` finds no long option of that name, but
`'d'` **is** in the short optstring, so it becomes `-d "evice"`, and
`lfs find`'s `case 'd'` takes `strtoul("evice")` — which is 0 and sets no
`errno` — as `--mindepth 0`.

### Verified rather than repeated

    lfind -device /dev/mapper/mds1_flakey --type f   exit 0, 8 FIDs
    lfind -local --type f                            exit 1
    lfind -internal --type f                         exit 1
    lfs find /mnt/lustre --mindepth evice -type d    exit 0

So the scan runs and says nothing, because the device also arrives as the
plain argument.  It is a spelling that quietly means nothing rather than
one that is refused, and the comment now says that.

**And the last line is why it is not fixed here.** `lfs find --mindepth
evice` is the same silent 0, so the looseness is `strtoul()`'s and
predates this series entirely.  Tightening it belongs to that option, in
its own patch, not to `lfind`'s option table — and would change
`lfs find`'s behaviour if done here.

## The coverage gap, and what I learned checking it

The whole-patch point:

> the lfind half of conf-sanity test_165 only exercises `--device` ...
> `--target`, `--local` and `--internal` have no coverage:
> `lfind_local_targets()` — the `osd-*/*/mntdev` glob, the `-MDT`/`-OST`
> filter, the MGS skip and the device de-duplication — is never run by
> the suite, and it is the most intricate new code in the patch.

Correct, and it names the difficulty: those forms need a mounted target,
so a case would have to run **before** the `stopall`, not in the block
after it.

I checked whether that is even possible, since `--local` finds targets
through a parameter that only exists while they are mounted, and a scan
of a live target is the case my notes had flagged as unreliable:

    # lfind --local --type f
    # lustre-MDT0000 (/dev/mapper/mds1_flakey)
    # lustre-MDT0001 (/dev/mapper/mds2_flakey)
    # lustre-OST0000 (/dev/mapper/ost1_flakey)
    # lustre-OST0001 (/dev/mapper/ost2_flakey)
    [0xe:0x0:0x0] ...

**It works, and it is intended.** `lfind.8` says so in as many words —
"a target that is in service is scanned without interrupting it" — and
carries a **Consistency** section for exactly this: the scan reports the
on-disk state, meets objects caught mid-update, and skips and counts
them.  My note that a live target scan is "blocked" was about the
remote-scan design question, not this.

So the gap **is** testable, before the `stopall`, and the enumeration
half can be asserted cheaply — the header lines name each target.  That
makes this the third coverage item owed to a test patch of its own, and
the most concrete:

1. `llapi_scan_changelog_test` is built but nothing runs it (68415);
2. nothing exercises `llapi_scan_fid()` at all (68416);
3. `--target`, `--local` and `--internal` are unexercised (68160), and
   `lfind_local_targets()` is the most intricate new code in that patch.

Not added tonight: a conf-sanity case wants a full setup/`stopall` cycle
to validate, and an unvalidated test is worse than a recorded gap.

## Verification

`lfs`, `lfind`, `liblustreapi` build under `-Werror`.  checkpatch 0
errors, 1 warning (the standing `Test-Parameters:` line).  18 changes, 18
Change-Ids.
