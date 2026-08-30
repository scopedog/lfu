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

## RESULT (2026-08-28): H3. The test is wrong, 68419 is right.

Reproduced on `rhel9.7-server-mgs-mds-clone`, MDSCOUNT=2, ldiskfs.
**The variable is how much changelog history exists before 160ac runs.**

| run | history | `oldest` vs `startrec` | verdict |
|---|---|---|---|
| `ONLY=160aa,160ab,160ac` | 160aa+160ab first | 87 > 2 | **PASS** x2 |
| `ONLY=160ac`, fresh format | none | 1 > 2 -> false | **FAIL** |

The failing run's probe:

    PROBE: mdt=lustre-MDT0000 surviving_records=2
    PROBE: users: current_index: 2
    PROBE: oldest_rec: 1 01CREAT ... a
    PROBE: oldest_rec: 2 01CREAT ... b
    PROBE: stale_find_exit=0            <-- should have refused
    PROBE: stale_find_out: /mnt/lustre/d160ac.sanity/b

**H1 and H2 are ruled out**: the log is not empty (2 records) and the record
does carry an index (`oldest = 1`, not 0). So `find_cl_oldest()`'s overloaded
`0` — the parked "empty vs quiet" design question — is **not** what failed
here. It stays a latent defect worth fixing on its own; it is not this one.

**H3 confirmed, and the guard is behaving correctly.** The cookie's `1` resumes
at `2` (the anchor is exclusive — worth knowing, and not obvious from the
test). The oldest surviving record is `1`. Nothing was purged between 1 and 2,
so the answer is complete and refusing would have been *wrong*. `lfs find`
returning `d160ac.sanity/b` is the right answer.

The bug is that the test **assumes** staleness instead of creating it. Writing
anchor `1` is only "older than the oldest surviving record" on a filesystem
that already has changelog history — which the Janitor has (its users are
`cl13` and `cl33`) and `review-dne-subtest-change` does not, because it runs
only the subtests the patch changed.

**The fix belongs in the test:** manufacture a real gap rather than assuming
one — take the anchor, write records the cookie has not consumed, `changelog_clear`
to purge them, then write one more. Then records between the anchor and the
oldest survivor really are gone, which is the condition the guard exists for,
and the test would fail against a build without the guard.

## The fix, and how it was verified (2026-08-28)

| condition | 160aa | 160ab | 160ac |
|---|---|---|---|
| all three, `ONLY_REPEAT=2` | PASS x2 | PASS x2 | PASS x2 |
| **each alone on a fresh fs**, `ONLY_REPEAT=2` | PASS x2 | PASS x2 | PASS x2 |
| **control** (`ARM=control`, refusal cut out) | — | — | **FAIL** |
| **control** (`ARM=noglimpse`, glimpse cut out) | — | **FAIL** | — |

The two control lines are the ones that matter: each test fails against a
library with the thing it checks removed, so it discriminates instead of
merely agreeing with the code beside it.

`ARM=noglimpse` neuters the condition rather than deleting the call --
deleting it leaves two static functions unreferenced and the tree builds with
`-Werror`, so the arm fails to compile instead of failing the test.

**FIXED 2026-08-28 (see `08-resolvedbg.sh` for how it was found).** The
instrumented run showed the decider being handed
`flags=0xc00000000000000` = `OBD_MD_FLLAZYSIZE | OBD_MD_FLLAZYBLOCKS` and no
`OBD_MD_FLSIZE`: the per-FID lookup answers from the MDT, whose size for a
striped file is the lazy SOM value, so `-size` was undecidable for every
object. `--resolve` now glimpses -- one `O_RDONLY` open and an `fstat`, the
same one `lfs find` does on an ordinary walk -- but only when `-size` or
`-blocks` is in the search, `--lazy` has not said the MDT's answer will do,
and the merged record has no strict size already. Widening it to the whole
demand mask would have put an OST round trip behind every `-uid` and
`-mtime` search, since one mask covers them all.

**A third defect, found by fixing the second.** Asserting that
`--changelog --resolve -size +0` returns something made 160ab fail. It is not
the assertion that is wrong -- `lfs-find.1` says `--resolve` exists so that
"options needing its state (`--size`, `--projid`, the layout options) can be
answered", and `06-sizeprobe.sh` shows it does not:

    === plain find -size +0 (no changelog) ===
      /mnt/lustre/szp/withdata            <- 11 bytes, matched
    === changelog --resolve -type f ===
      /mnt/lustre/szp/withdata            <- resolve itself works
      /mnt/lustre/szp/empty
    === changelog --resolve -size +0 ===
      lfs find: 2 objects could not be decided: the changelog has no answer
                for a field the search asked for

So `--resolve` resolves the name but does not fill the size. The old test
passed only because it checked the exit status and never looked at the output
-- a vacuous assertion hiding a real defect, which is the same shape as
68414's `test_160za`. 160ab now asserts acceptance and deliberately not the
answer, with the reason in the test, so nothing encodes the gap as correct.
**The `--resolve` defect itself is unfixed and belongs to 68416/68418.**

## Stages

| script | where | what |
|---|---|---|
| `00-patches.sh` | **local** | cuts `5afbab284e..191c17a792` (68420 PS2) and scps it to the instance |
| `01-prereq.sh` | instance | repos and build prerequisites; unchanged from `lab-dne166/` |
| `02-build.sh` | instance | builds the series, and **refuses to continue if 160ac is absent or gated above the tree** |
| `03-probe.sh` | instance | runs `$ONLY` under `ONLY_REPEAT`; `PROBE=1` instruments the stale-cookie block |
| `04-arms.sh` | instance | `ARM=post` / `ARM=control`, and checks WHICH arm got installed |
| `06-sizeprobe.sh` | instance | does `-size` survive `--changelog --resolve`? (no) |

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

## Round 14 (2026-08-29): 68419 PS2's cookie parse, and its two arms

Three of the four AI comments on 68419 PS2 were about `find_cookie_read()` /
`find_cookie_write()`, and one of them was a live out-of-bounds write.  160ac
gained a case for each of the two that a test can reach.

| arm | what is cut | 160ac |
|---|---|---|
| `post` | the tree as committed | **PASS** x2 |
| `nobound` | the signed bound test put back (`(int)mdt >= nstarts`) | **FAIL** |
| `noheader` | the foreign-cookie refusal cut out | **FAIL** |

**`nobound` dies rather than merely disagreeing**, which is the point:

    sanity.sh: line 22821: 70762 Segmentation fault (core dumped)
        $LFS find $DIR/$tdir --since-cookie $ck.bad -type f > /dev/null
    sanity test_160ac: @@@@@@ FAIL: a negative MDT index should be ignored

`%x` accepts a sign, so a cookie line of `<fsname>-MDT-1 42` parses to
`0xffffffff`; as `(int)` that is -1, which passes `>= nstarts`, and
`starts[0xffffffffu]` then lands 32GiB past a 64-entry array.  Confirmed
outside the lab too, with a four-line probe: `-MDT-1` -> `0xffffffff`,
`-MDT-800` -> `0xfffff800`, both accepted by the old test and both rejected by
`mdt >= (unsigned int)nstarts`.

The whole round ran on one VM: **160y, 160z, 160aa, 160ab, 160ac, 160ad all
PASS x2, SKIP=0**, MDSCOUNT=2, ldiskfs.  160y and 160z are 68413/68414, which
are not in the 16-commit stack -- the lab branch is base + those two + the
stack, so one build covers both series.

## Three traps this lab hit in round 14

**`03-probe.sh` reads `$HOME` before it sets it.**  Under `sudo` that is
already `/root`, so `L` becomes `/root/lustre-160ac`, the `cd` fails, and the
run ends having tested nothing while still printing a tidy-looking cleanup.
Pass `LTREE=` explicitly.

**A root-owned log file makes a build "fail" that never ran.**  The arm script
redirected to `/tmp/arm-make.log`, left root-owned by an earlier `sudo` run;
the redirect failed, the `make` never executed, and the `|| { BUILD FAILED;
tail ...; }` branch printed **the previous run's log**, which looks exactly
like a build that ran.  The logs live under `$HOME` now.

**`make install` needs the filesystem unmounted.**  `/sbin/mount.lustre` is
"Device or resource busy" while anything Lustre is mounted, so an arm built
between two runs installs nothing and the next run silently reports on the
arm before it.  `llmountcleanup.sh` first.

## Round 15 (2026-08-30): the AI sweep, and the LAST_ID control

`11-run-r15.sh` and `12-conf-r15.sh` are the round's two runs, on `lab-r15b`
(base + 68413 + 68414 + the 16), `rhel9.7-server-mgs-mds-clone`, MDSCOUNT=2,
ldiskfs, `ONLY_REPEAT=2`:

| run | result |
|---|---|
| sanity `157c,160aa,160ab,160ac,160ad,160y,160z` | **PASS x2 each, SKIP 0** |
| conf-sanity `165,166` | **PASS x2 each** |

166 is not vacuous: *"client sees 21 names over 20 objects / --fid2path
resolved 20 objects from 21 names, hardlink once"*.

**The control that matters this round is `ostprobe.sh` + `cut-lastid.py`.**
Neither 165 nor 166 scans an OST, so the defect 68288's review found -- an
`O/<seq>/LAST_ID` classified as a data object, `fid2path` answering -EINVAL
for it, the sweep exiting non-zero on a healthy filesystem -- has no test to
fail against.  So it was cut back in:

| arm | `lfind --local --fid2path /mnt/lustre` |
|---|---|
| the tree as committed | **exit=0**, 63 OST objects counted, no error |
| `cut-lastid.py` (the classify order and the -EINVAL arm put back) | **exit=1**, `cannot resolve [0x280000400:0x0:0x0] ... Invalid argument (22)` |

`0x280000400:0x0:0x0` is the LAST_ID itself -- f_oid 0, which is exactly what
`fid_is_namespace_visible()` excludes.  The lab build was restored to the
committed tree afterwards and the probe rerun to confirm exit=0.

**`lfind --device` wants the target's `mntdev`**, and `obdfilter.*.mntdev` was
empty on this node, so the OST-alone arm of the probe fell through to a ZFS
guess and answered -ENOTSUP. `--local` is the arm that works here.
