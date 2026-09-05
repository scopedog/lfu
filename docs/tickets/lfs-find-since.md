# LU-20650 — `lfs find --since` and `--changelog`

**Status:** filed as LU-20650 on 2026-08-26. One of the three pieces is
written and a second one now is, both on branch `lu-20650-since` in
`~/projects/lustre/lustre-scanfid`:

| | commit | state |
|---|---|---|
| `llapi_scan_fid()` | `f1e4165425` | built, reviewed, lab-verified |
| `lfs find --since` | `5bbf8f6318` | built, reviewed, lab-verified |
| `lfs find --changelog` | `e0265228c5` | built, reviewed, lab-verified |
| `lfs find --since-cookie` | `a394dccfd3` | built, reviewed, lab-verified |

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

### `--changelog`, verified

Verified on the cluster 2026-08-26. Everything below behaved as §13.1 says:

| | |
|---|---|
| `--changelog all --since 2m` | prints the objects with events, and reports *"7 objects have no pathname and are named by FID"* — rule 3 |
| `-type f` / `-type d` | answer from the creation the record carries |
| `-size` without `--resolve` | refused, naming itself and `--resolve` |
| `-mtime -1` | refused: *"a changelog records an event time, not an object time; say `--since 1d`"* |
| a subtree path | refused, naming the mount and `--resolve` — rule 2 |
| `--maxdepth` | refused, noting `--since` honours it |
| an MDT that does not exist | refused, naming the filesystem |
| `--resolve -size` | let through, and answers |

**`-type` was broken, and the cause was in LU-20649, not here.** See below.

### Also still open

- **The three `sanity` cases have not been run by the test framework.** See
  below.
- `--changelog` with `--resolve` merges correctly by construction but has no
  test that a recorded uid survives the lookup — worth one before push.

---

## The `-type` bug, and where it actually was

`lfs find --changelog all -type f` returned nothing. Two guesses were wrong
before the data settled it, which is the point worth keeping.

**Guess one, wrong:** `find_decide()`'s type check reads `stx_mode` as zero and
calls it a miss rather than a don't-know. A fix there **never fired**, so it was
reverted rather than left unverified in the function all three entry points
share.

**Guess two, wrong:** `find_prefilter()` was skipping records that had no type.

**What the data said.** A twenty-line program that read the coalesced stream and
printed `sr_valid` and the mode per record:

```
	fid=[0x200007161:0x3f:0x0] valid=0x14204001 TYPE=yes mode=0000000(zero) evt=11 name=afile
	fid=[0x200007161:0x40:0x0] valid=0x14204001 TYPE=yes mode=0040000(DIR)  evt=2  name=adir
```

`TYPE=yes` with `mode` **zero**. The record claimed to know its type and carried
nothing for it, so `find_prefilter()` compared 0 against `S_IFREG`, missed, and
skipped — silently, because a confident wrong answer is not undecided.

**The cause, in `scan_cl_absorb()` (LU-20649):**

```c
	o->co_mode = scan_cl_mode(r->cr_type);	/* assigned every event */
	if (o->co_mode != 0)
		o->co_valid |= LLAPI_SCAN_TYPE;	/* only ever OR'd in */
```

Only a creation implies a type. `afile` was CREAT (mode `S_IFREG`, bit set) then
OPEN and CLOSE (mode 0, bit **stays**). Coalescing left it claiming to know its
type and carrying zero — which is exactly what the validity mask exists to keep
apart: *"cannot answer"* from *"the answer is zero"*.

The fix only overwrites the mode when the new event actually implies one, so a
creation's answer stands for every event after it. An object's type does not
change. Folded into `e18638d331`, LU-20649's own commit, and the three LU-20650
commits rebased on top with their Change-Ids intact.

Verified after: the same record reads `mode=0100000(REG)`, `-type f` returns the
file and `-type d` the directories.

---

## `--since-cookie`, and the off-by-one only the lab could find

The file is a line per MDT, `<mdtname> <index>`, read as the anchors and
rewritten with the indexes the run reached — written whole and renamed over, so
an interrupted run leaves the previous anchors rather than half of the new ones.

Six cases verified on the cluster:

| | |
|---|---|
| first run, no cookie file | reads from the oldest record, writes the cookie |
| second run, same cookie | returns only what changed since |
| third run, nothing changed | returns nothing |
| cookie older than the oldest surviving record | refused, naming both indexes, `-ESTALE` |
| cookie from another filesystem | ignored, not used as an anchor |
| `--since` and `--since-cookie` together | refused |

**The off-by-one.** With a wide changelog mask the first test looked like it
worked, because every `lfs find` run generates OPEN and CLOSE events of its own
and the extra objects looked like those. Re-running with a narrow mask made it
unmistakable: **every run repeated the last object of the previous one**. The
cookie holds the last index consumed and `sc_startrec` is inclusive — as
`lfs changelog MDT <startrec>` is — so the next run has to start one past it.

Worth keeping: the wide mask hid the bug behind a plausible explanation I had
already accepted once. Narrowing it was what turned "that's probably the reads"
into a reproducible off-by-one.

Two more things review caught before it ran: `sscanf("%s")` into a fixed buffer
from a file the caller controls, and a cookie from another filesystem being
accepted as an anchor for this one.

---

## Man page and tests — `d1b91aafd5`

`lfs-find.1` documents `--since`, `--since-cookie`, `--changelog` and
`--resolve`: what each answers, that `--since` is a strict subset of the same
search without it, that a bare index belongs to one MDT, that a number which
could be an index or an epoch second is never guessed at, and that reading a
changelog neither consumes it nor needs a registered user — while records exist
only while some user is registered. It renders clean under `man --warnings`,
and `checkpatch-man` reports only the file's pre-existing `BASH COMPLETION`
section name.

Three cases: **160aa** asserts the property rather than a filename — that
`--since`'s answer is a subset of the same find without it, and smaller — so it
does not depend on what else the filesystem is doing. **160ab** walks the five
refusals and then shows `--resolve` letting `-size` through. **160ac** runs the
cookie three times, then a stale anchor and both anchors together.

`160ac` asks for creations only. A wide mask records the test's own reads, and
then "nothing changed since" is never true — which is exactly what hid the
cookie's off-by-one. Verified against the MDT that `changelog_mask=creat`
yields `MARK CREAT`, which is what the test needs.

### The caveat that matters

**These three have not been run by `sanity.sh`.** The cluster has never had the
test framework on it — only the stock `cfg/local.sh`, no config naming our three
nodes, no `/tmp/test_logs` — and standing it up means letting the framework
mount and reformat the filesystem, which is its own piece of work.

What *is* verified: every behaviour the three assert was exercised by hand
against this cluster while the flags were being written, and `bash -n` parses.
What is **not**: the framework interaction — helper semantics, `stack_trap`
ordering, `error` usage, whether `comm` with process substitution behaves inside
a test function. Those are exactly the mistakes a first autotest run finds, and
this series has ten of them behind it to say that is not a hypothetical.
