# The case for pushing round 20 — for the user to weigh

**Not pushed. Not pushing.** [[ask-before-gerrit-push]] is standing and
this is the argument, not an action.

## What reviewers are currently looking at

Gerrit holds round 19. Round 20 — everything from tonight — is local.
That gap is now costing other people's attention:

| what | on Gerrit | locally |
|---|---|---|
| `sanity 56El` | **failing on every change from 68095 up**, both backends, every CI run since 19:00 | fixed, with a before/after control |
| 68616's four AI threads | reported open again on PS2 | all four fixed in round 20 |
| 68617's AI thread | reported open again on PS1 | fixed in round 20 — the page already reads `.\" Added in commit 0.9.1`, and `checkpatch-man` already gives the `0 errors, 0 warnings, 1 checks` the comment asks for |
| 68095's `977519ad` | the Gerrit AI spent a full review finding the 56El root cause | found and fixed hours earlier by lreview |

The last row is the clearest waste: **two independent reviewers spent a
full pass each arriving at the same bug**, because the fix for it is
sitting on this machine.

## Being fair about the rest

Most of adilger's comments are **not** stale, and it would be wrong to
argue otherwise:

- his **15 on 68094** are new API-design questions that round 20 does not
  touch and could not have pre-empted;
- his **two on 68095** were live — the dead version gate and the tmpfs
  rationale — and were acted on tonight *because* he raised them;
- his 68231 comment is a "Done", and his 68616 one is a decline
  ("not critical, and patch is still an improvement").

Only his 68617 comment — "could be done if patch needs to be refreshed
for some other reason" — turns out to be already satisfied.

So the argument is not "adilger is wasting his time". It is narrower and
still real: **CI cannot go green while 56El is unfixed on Gerrit**, and
the AI reviewers re-derive fixed problems on every patchset.

## Against pushing now

- adilger is **mid-series** and said so: "Just going through the series
  ... I'm not sure whether I'll have the same thoughts as I get to the
  end." A push now rebases everything under him.
- His four structural questions are unanswered. If any of them lands,
  the record and parameter API change shape, and round 20's
  parameter-handling work would be rewritten anyway.
- [[gerrit-push-cadence]]: one patchset per review cycle, not per
  finding. This *is* one cycle's worth — but the cycle may not be over.

## What I would suggest

Ask adilger whether he would rather have the series refreshed now — with
56El fixed so CI can go green and the AI stops re-finding it — or finish
his pass over the current patchsets first. That is a one-line question
that costs nothing and settles the timing, and it is his review being
spent either way.

If the answer is "refresh now", round 20 is ready: 18 changes, 18
Change-Ids, `-Werror` clean, checkpatch 0 errors, and the lab green on
`sanity 56El`, `160aa`–`160ad`, `llapi_scan_test` 11/11 and
`llapi_scan_device_test` 7/7.
