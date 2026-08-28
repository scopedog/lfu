# Lab — sanity 160ac, "a stale cookie should be refused" (LU-20650 / 68419)

`review-dne-subtest-change` **and** `review-dne-zfs-subtest-change` both failed
68420 PS2 on `test_160ac` with

    Error: 'a stale cookie should be refused'

i.e. `lfs find --since-cookie` returned 0 where it had to refuse. The Janitor
ran the same three tests on the same patchset and **passed** them on both
backends (job 69012: 160aa/ab/ac PASS, ldiskfs+DNE and zfs). Pass once, fail
under `ONLY_REPEAT` — the same shape as test_166.

## What the lab is for

Three readings fit every fact available from outside, and they need **opposite
fixes**. The probe prints the one number that separates them: the index of the
oldest surviving changelog record, against the cookie's hardcoded `1`.

| | what happened | `oldest` | whose bug |
|---|---|---|---|
| **H1** | changelog is empty | `0` — guard disabled | 68419 |
| **H2** | first record has no `LLAPI_SCAN_EVENT`, so `find_cl_first_cb` stores `0` and stops | `0` — guard disabled | 68419 |
| **H3** | the oldest record really **is** index 1 | `1` — `1 > 1` false, guard is CORRECT | the test |

The guard:

```c
*oldest = 0;
rc = llapi_scan_changelog(&sc, find_cl_first_cb, oldest);
/* the callback's own 1 comes back; an empty log is not an error */
return rc < 0 ? rc : 0;
...
if (sc.sc_startrec != 0 && oldest > sc.sc_startrec)   /* oldest > 1 */
```

`0` is overloaded three ways — empty log, record without an index, and no
anchor — and two of them silently disable a check whose whole purpose is to
refuse a short answer.

**H3 is live because the Janitor's own log shows how much history it had:**
`Registered 2 changelog users: 'cl33 cl13'` — the 33rd and 13th users on that
filesystem. `subtest-change` runs *only* the three changed subtests, so its MDT
is nearly pristine and its indices are small. The test hardcodes `1` as
"definitely older than the oldest record", which is only true on a filesystem
with history.

## Stages

| script | where | what |
|---|---|---|
| `00-patches.sh` | **local** | cuts `5afbab284e..191c17a792` (68420 PS2) and scps it to the instance |
| `01-prereq.sh` | instance | repos and build prerequisites; unchanged from `lab-dne166/` |
| `02-build.sh` | instance | builds the series, and **refuses to continue if 160ac is absent or gated above the tree** |
| `03-probe.sh` | instance | `ONLY=160aa,160ab,160ac ONLY_REPEAT=2`, with the stale-cookie block instrumented |

One `c3-standard-8` rocky-linux-9 instance; MGS + 2 MDTs + OST + client on it.

## Two things this lab must not repeat

**A skipped test proves nothing.** `03-probe.sh` tallies SKIP and says so, and
`02-build.sh` fails outright if 160ac is missing or still gated at 2.17.58.
That is the trap that let 68420 take `Verified+1` while testing nothing.

**A new test is verified by FAILING against the unfixed code**, not by passing.
This run is the "unfixed" arm on purpose — if 160ac passes here, the
reproduction has failed and the fix cannot be validated against it. See the
`test_160za` note in the known-noise record, where a new test passed against
broken code and only a control caught it.

## Two traps this lab hit on its first run, both guarded now

**`~/lustre-release` on the lab VM is somebody's working tree.** On
`rhel9.7-server-mgs-mds-clone` it had uncommitted edits to `mdd_changelog.c`
and `lwp_dev.c`, ten local branches of unrelated work, and a `master` **216
commits ahead of origin**. The first draft of `02-build.sh` would have run
`reset --hard` and `clean -fdx` in it. It now builds in `$LTREE`
(`~/lustre-160ac`, a hardlinked local clone, so it costs seconds) and
**refuses outright if `LTREE` is `~/lustre-release`**. "Clone VM" does not mean
disposable.

**`git fetch origin master` without `--tags` silently builds the wrong
version.** `LUSTRE_VERSION` comes from `git describe`, and the clone's newest
tag was `2.17.51`, so the build installed `lfs 2.17.51_737` — *below* the
`2.17.57` gate, which would have skipped all three tests while the lab looked
like it ran. With `--tags` the same tree describes as `v2_17_57-59`, matching
the round-11 record's `2.17.57_59`. So `02-build.sh` asserts the **installed**
version after `make install`, not just the gate in the source: the source gate
being right does not mean the binary clears it.

## Why one node and ldiskfs

Both backends failed identically, so the cause is not backend-specific, and the
Janitor's passing run was `ldiskfs+DNE`, so DNE is not the discriminator either.
`MDSCOUNT=2` is kept for fidelity with `subtest-change`, not because DNE is
suspected. `ONLY_REPEAT` is the variable — as in `lab-dne166/`.
