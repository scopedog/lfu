# The `_ONCE` lab: `--since` prints each path once (2026-09-06)

VM `rhel9.7-server-mgs-mds-clone`, RHEL 9.7, ldiskfs, MDSCOUNT=2, OSTCOUNT=1,
built from `~/lustre-once` at `2.17.57_63_gce50404`. Two branches in one tree:
`lab/fixed` (the series with `LLAPI_SCAN_CL_F_ONCE`) and `lab/unfixed` (the
same series without it), so the arms are paired on one build of the modules —
the change is entirely userspace.

## The fixture, built once

600s of stream time cannot be faked, so the duplicate is forced through the
other bound: `sc_max_cached` is 100000, so 100010 objects between one file's
two events evict it and the scanner delivers it twice.

    mkdir /mnt/lustre/onced; touch onced/twice
    createmany -m onced/f 100010      # mknod: no OST object per file
    echo x >> onced/twice

100011 entries in 20s; MDT inodes 100545/162704. Every arm read it untouched.

## The paired result

| arm | build | lines for `onced/twice` |
|---|---|---|
| `lfs find --since 1h -name twice` | `lab/unfixed` | **2** |
| `lfs find --since 1h -name twice` | `lab/fixed` | **1** |
| `lfs find --changelog lustre-MDT0000 --since 1h` | `lab/fixed` | 1 |

The unfixed arm prints `/mnt/lustre/onced/twice` twice; the fixed arm prints
it once, and the run's own summary line moves from **100022** changed objects
to **100021** — the duplicate `llapi_scan_fid()` is not paid either.

`--changelog` keeps its repeat but does not print it: the second delivery is a
fresh cache entry holding only the append, which carries no name, so `-name`
cannot be decided from it — the run says *"1 objects could not be decided from
their changelog record"*. That is the mode's documented behaviour and the
reason it does not set the flag.

## The library's own test

`llapi_scan_changelog_test -m lustre-MDT0001 -d /mnt/lustre`, all six cases:

    test5: _ONCE delivers an object once where object mode repeats it
      [0x240000402:0x8:0x0] arrives 2 times, once with _ONCE; 15 records of 17
    all tests passed

test5 asserts its own premise first — without the flag the object *must* arrive
more than once, or there is nothing to suppress — and `sc_max_cached = 1` makes
that deterministic in milliseconds. test4 now refuses eight bad calls,
`_ONCE` without `_COALESCE` among them.

## Two lab traps, neither a defect in the round

- **The test's `-m` must name the MDT its own directory landed on.** Under
  DNE the harness creates `llapi_scan_changelog_test.d` wherever the balance
  puts it — here MDT0001 — while `-m lustre-MDT0000` reads the other log, so
  test0 fails with *"no CL_RENAME in the stream"* and the records it is
  looking at are somebody else's.
- **`-u <user>` fails on this tree** with *"cannot set changelog filter: No
  such file or directory"*, and afterwards the MDT's `changelog_mask` reads
  `MARK` alone. Stock `lfs changelog --user cl1` fails identically, and this
  tree carries **none of 68340/68413/68414** — LU-20647 is *"mdd: look up a
  changelog user of either record type"* and LU-20648 *"mdc: fix changelog
  mask composition"*, which is exactly this. Not this round's, and the run
  works without `-u`.

## The regression run

`sanity.sh ONLY=56El,157c,160aa,160ab,160ac,160ad ONLY_REPEAT=2` on
`lab/fixed`, after a full `make install` with everything unmounted:

    56El  PASS:2   157c  PASS:2   160aa PASS:2
    160ab PASS:2   160ac PASS:2   160ad PASS:2

Zero skips, zero failures, no `error:` lines. `160y` and `160z` were in the
requested list but are **not in this tree** — they arrive with 68413/68414,
which this branch does not carry — so they ran not at all rather than
skipping, which is why the tally shows 0/0/0 for them.

## Verdict

The defect reproduces (2 lines), the flag removes it (1 line), the object is
still in the answer, the duplicate lookup is saved, and the six sanity cases
that cover this code are green twice over.
