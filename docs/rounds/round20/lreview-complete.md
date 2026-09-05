# lreview across the series — complete

All twelve un-reviewed changes reviewed, one at a time. **~$77, ~2h40m
of review wall-clock**, 27 findings.

| change | findings | outcome | cost |
|---|---|---|---|
| 68094 | 4 | 3 real — **caught a fix of mine that fixed nothing**; reverted | $8.42 |
| 68095 | 2 | **found the 56El root cause**, open since the first tick | — |
| 68415 | 4 | 3 fixed, 1 held (API shape) | $9.13 |
| 68416 | 4 | 4 fixed | $4.32 |
| 68417 | 3 | 3 fixed — severity medium | $11.68 |
| 68420 | 5 | 4 fixed, 1 held against the maintainer | $8.06 |
| 68158 | 4 | 3 fixed, 1 declined | $5.86 |
| 68160 | 1 | 1 fixed | $5.77 |
| 68157 | 1 | **declined — would have been a regression** | $4.39 |
| 68231 | 0 | **clean** | $2.80 |
| 68616 | 3 | 2 fixed, 1 recorded | $3.64 |
| 68617 | 1 | 1 fixed | $3.43 |

## What it was worth

**The 56El root cause.** Open all evening, three ticks of ruling things
out, and 68095's review named it: `-printf` sets `gather_all`, the
project-id fetch is not tolerant of an object off Lustre, and both its
arms answer `ENOTTY` — one on any kernel, one below Linux 6.0, which is
the whole rocky8.10-versus-rhel9.7 difference. That alone justified the
run.

**It caught a mistake of mine.** 68094's review found that
`scan_size_ok()` — which I had added hours earlier across five commits —
fixed nothing, because `scan_param_whole()` already rounded the size down
to a whole field, and that the two mechanisms contradicted each other.
Reverted. A real bug was underneath it on the changelog parameter, which
is why the round was not wasted.

**And I declined it twice, with reasons.** On 68157 its suggestion would
have collapsed `-ENOTSUP` and `-ENOTTY`, which are different answers, and
reported `DEFAULT_PROJID` for an object a target could not answer for.
On 68158 its API cleanup would change a shared entry point's exit codes
while adilger has open questions about exactly that kind of contract.

## Two failure modes worth remembering

**It fails at zero cost and looks like success.** 68231, 68616 and 68617
all "finished" within one minute of each other, `rc=0`, and the driver
marked them done. The logs said `claude exited 1 — 0 tok, $0.00`. Had I
trusted the driver's own bookkeeping, three changes would have been
recorded as reviewed without ever being read. **Check the token count,
not the exit status.**

**It reasons about one commit and the series moves.** Several findings
were right about the commit in isolation and wrong about the tip —
68157's error codes most sharply. The inverse is also true and more
useful: it caught **four** places where a patch was written for the tip
rather than for its own position in the series, which the whole-change
Gerrit AI has never once flagged.

## Verification of the whole stack

    18 commits, 18 Change-Ids, working tree clean
    lfs, lfind, liblustreapi build under -Werror
    checkpatch: 0 errors across all 18 commits

Lab, ldiskfs MDSCOUNT=2 OSTCOUNT=2:

    sanity 56El, 160aa, 160ab, 160ac, 160ad   all PASS
    llapi_scan_test                           11 of 11
    llapi_scan_device_test                     7 of 7

## What is left, and it is all the user's

1. **adilger's four structural questions on 68094** — three are
   alternative answers to one question, so guessing costs the other two.
   His nanosecond comment is marked a defect and is answered for free by
   the `struct statx` option.
2. **The version-gate conflict** — lreview wants them back, adilger
   removed them. His answer kept; the mechanism lreview names is real.
3. **The `--since` duplicate-lines trade-off** — untouched.
4. **Whether to push** — see the push case; CI cannot go green while
   56El is unfixed on Gerrit.
5. **A test patch of its own**, for three uncovered things:
   `llapi_scan_changelog_test` built but never run,
   `llapi_scan_fid()` unexercised, and `lfind --target/--local/--internal`
   untested.
