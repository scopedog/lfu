# LU-20650 — `lfs find --since` and `--changelog`

**Status:** filed as LU-20650 on 2026-08-26. One of the three pieces is
written and a second one now is, both on branch `lu-20650-since` in
`~/projects/lustre/lustre-scanfid`:

| | commit | state |
|---|---|---|
| `llapi_scan_fid()` | `f1e4165425` | built, reviewed, lab-verified |
| `lfs find --since` | `5bbf8f6318` | built, reviewed, lab-verified |
| `lfs find --changelog` | `7d3a02579f` | built, reviewed, lab-verified except `-type` |

Neither is pushed.

**Jira:** [LU-20650](https://jira.whamcloud.com/browse/LU-20650) ·
**Type:** Technical task (as LU-20603, LU-20605,
LU-20611, LU-20613, LU-20649 are) · **Epic:** LU-20462 · **Relates to:**
LU-20605 (which made `find_decide()` take a record) and LU-20649 (which reads
the changelog into one)

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim;
do not reflow it. Rules are in `changelog-user-lookup.md`.

---

## Summary (as filed)

```
LFU: lfs find --since and --changelog, the changelog as a find source
```

## Description (paste verbatim into Jira)

LU-20649 reads an MDT changelog into a {{struct llapi_scan_rec}}. This is what
reaches a user: two spellings of {{lfs find}} that search one, and the mount-side
call the first of them needs.

*The one-line difference between them:* {{--since}} answers *as it is now* —
every candidate from the log is verified against the live object — and
{{--changelog}} answers *as it was recorded*. That is why {{-name}} under
{{--changelog}} matches the name in the event and not the object's current
name, and why an unlinked object appears under {{--changelog}} and cannot
under {{--since}}.

h3. Three pieces

* {{llapi_scan_fid()}} — fill a record for one FID through a mount, the way a walk fills one. *Written; see the note below.*
* {{lfs find --since}} — the changelog as a candidate set, each candidate verified. The result is a strict subset of an ordinary find: narrowed, never wrong.
* {{lfs find --changelog}} — the changelog as the whole source, with the three rules below.

h3. Why {{--since}} is a composition and not a scanner flag

A walk cannot skip to the changed objects. {{--since}} inside
{{llapi_scan_namespace()}} would read the log and then walk everything anyway,
so it lives above the scanners: candidates from {{llapi_scan_changelog()}} in
object mode, each filled by {{llapi_scan_fid()}}, each judged by the existing
{{find_decide()}}. No new predicates and no second copy of the vocabulary.

h3. The three rules that keep the two flags apart

# A predicate the changelog cannot answer is refused, not approximated, unless {{--resolve}} is given. {{-type}} is the one that straddles: a creation records it and nothing else does, so without {{--resolve}} it matches creations and counts the rest undecided.
# Under {{--changelog}} the path argument means the mount, not a subtree, because a changelog is per-MDT and knows nothing about where an object sits.
# Output is a pathname where one exists and a FID where one does not. An unlinked object has no pathname, and printing its FID is the whole point of asking.

Resolution fills, and never removes or overrides: adding {{--resolve}} must not
make the answer smaller.

h3. What {{--since}} takes

* {{--since TIME}} — the first record at or after it, per MDT. The human spelling, and the only one that means the same thing on every MDT.
* {{--since INDEX}} — only with an explicit single {{--changelog MDT}}, or on a single-MDT filesystem. Refused otherwise, naming the ambiguity, because {{cr_index}} is per-MDT.
* {{--since-cookie FILE}} — per-MDT indexes written by a previous run, rewritten at the end. The machine spelling, and what a repeated job should use.

A bare number is never guessed between an index and an epoch second.

h3. Acceptance

* {{lfs find --since}} returns a subset of what the same predicates return without it, on the same filesystem, with no predicate answering differently.
* A predicate {{--changelog}} cannot answer is refused with the predicate named, or counted undecided where rule 1 says so.
* An object unlinked during the window appears under {{--changelog}} and not under {{--since}}.
* {{sanity}} cases for both, and for the refusals.

---

## Notes for us, not for the ticket

### The retitle — done

The commit carried `LU-20649` and should not have: LU-20649 is filed as the
changelog *library* half, and its own description says "This is the library
half only. `lfs find --since` and `lfs find --changelog` are a separate
change." Retitled to LU-20650 on 2026-08-26, branch renamed
`lu-20649-scan-fid` → `lu-20650-scan-fid`, Change-Id unchanged so Gerrit sees
one change and not two.

### Why not LU-20605

Asked on 2026-08-26. LU-20605 is filed as *"a behaviour-preserving change of
internals"* with the acceptance criterion that `sanity.sh::test_56*` stays
green, and it already carves out adjacent work by name. Two new user-facing
flags are the opposite of behaviour-preserving. It is also In Progress with
68095 at patchset 9 and Verified+1, and widening a ticket under active review
stalls it. The real relationship — `find_decide()` taking a record is what
makes a third source possible — is a dependency, and belongs in a "relates to"
link.

### Still open

- **A batch form for `--since`.** One `fid2path` and one gather per candidate
  is two RPCs per object where a walk pays roughly one. Measure a real window
  before adding an API for it (`design-llapi-scan-fid.md` §6).
- **Clock skew under DNE**, and who owns the `--since-cookie`. One of the three
  items the 2026-08-26 meeting was to settle.
- **`llapi_scan_changelog_test` is still not wired into a suite** — LU-20649's
  problem, but a reviewer meeting both at once will ask.

### What `--since` does and does not do yet

Verified on the cluster 2026-08-26: against 7 regular files of which 2 changed
inside the window, `--since 4s -type f` returned exactly those 2 — a strict
subset — with `rc=0`; the subtree restriction held; a bare index was accepted
on the single-MDT filesystem and returned all 7; and `-type d` over the same
window answered for directories.

Not done, and known:

- **`--changelog`** — the event view, with §13.1's three rules.
- **`--since-cookie`** — the machine spelling, and where the stale-anchor
  check belongs.
- **A time anchor reads the log from its oldest surviving record** and cuts on
  the record's own event time, because a time cannot become a per-MDT index
  without reading it. Correct, and O(log) rather than O(window).
- **No man page or `sanity` case yet** for `--since` itself.

### A trap the lab set for me

The first run of the `--since` test piped stderr to `/dev/null`, and the
output looked perfect: exactly the two changed files. It was wrong. The MDT
enumeration was walking 64 phantom targets and failing at `testfs-MDT0001`,
so the command printed the right answer and then exited non-zero. Hiding
stderr in a test hides the half of the result that says whether to believe the
other half.

### `--changelog`, and the one thing left in it

Verified on the cluster 2026-08-26. Everything below behaved as §13.1 says:

| | |
|---|---|
| `--changelog all --since 2m` | prints the objects with events, and reports *"7 objects have no pathname and are named by FID"* — rule 3 |
| `-size` without `--resolve` | refused, naming itself and `--resolve` |
| `-mtime -1` | refused: *"a changelog records an event time, not an object time; say `--since 1d`"* |
| a subtree path | refused, naming the mount and `--resolve` — rule 2 |
| `--maxdepth` | refused, noting `--since` honours it |
| an MDT that does not exist | refused, naming the filesystem |
| `--resolve -size` | let through, and answers |

**The gap: `-type` under `--changelog` returns nothing** where the design says
it should match the creations and count the rest undecided. It is not the
`find_decide()` type check — a fix there never fired, so it was reverted rather
than left in shared code unverified. The skip happens earlier, in
`find_prefilter()`: when a coalesced record carries `LLAPI_SCAN_TYPE` at all,
the prefilter compares it and returns "skip" on a mismatch, and when it does
not carry it the record reaches `find_decide()` with `stx_mode` zero. Which of
those two is happening here is the next thing to find out — instrument the
callback and print `sr_valid` per record.

Everything else in `--changelog` is independent of it and works.

### Also still open

- `--since-cookie`, and the stale-anchor check that belongs with it.
- No man page or `sanity` case for either flag yet.
- `--changelog` with `--resolve` merges correctly by construction but has no
  test that a recorded uid survives the lookup — worth one before push.
