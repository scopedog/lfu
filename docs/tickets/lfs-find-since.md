# LU-XXXXX — `lfs find --since` and `--changelog`

**Status:** drafted 2026-08-26, not yet filed. One of the three pieces is
already written: `llapi_scan_fid()` is `c3cf4c1073` on branch
`lu-20649-scan-fid`, currently mislabelled LU-20649 and to be retitled to this
number once it exists.

**Jira:** to be filed · **Type:** Technical task (as LU-20603, LU-20605,
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

### The retitle

`c3cf4c1073` carries `LU-20649` in its subject and should not: LU-20649 is
filed as the changelog *library* half, and its own description says "This is
the library half only. `lfs find --since` and `lfs find --changelog` are a
separate change." Retitle to this ticket once it has a number. The Change-Id
`I796db84d3fe596b1cfa93658dcfeb240db8e33a5` stays, so nothing is lost.

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
