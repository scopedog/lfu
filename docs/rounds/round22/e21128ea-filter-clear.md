# 68415 `e21128ea`: a filtered record stalled `_CLEAR`

The AI's second defect of the 2026-09-06 evening round, verified and fixed as
asked.

## The finding, confirmed against the tree

`scan_cl_deliver()` returns as soon as `sc_filter` rejects a record — it bumps
`ss_filtered` and nothing else — while `sl_accepted` is assigned only on the
accept path at the bottom. `scan_cl_clear()` opens with `upto =
sl->sl_accepted` and returns on `upto == 0`.

So a consumer that uses `sc_filter` to select — CL_UNLINK out of a log that is
mostly CL_CLOSE — with `LLAPI_SCAN_CL_F_CLEAR` set **never clears anything**,
and the registered user's backlog grows without bound: the failure the man
page's own NOTES section warns about, reached through a pair of options the
library offers. On a mixed stream it is milder and still real — the tail of
filtered records after the last accepted one is re-read on every run.

Both modes reach it: `scan_cl_event()` and the two cache paths all deliver
through that one function.

## It was an asymmetry in our own code

The `_ONCE` suppression added earlier the same day already advances
`sl_accepted`, with a comment saying why — *"the records were consumed, and
holding it back would stall `_CLEAR` on a log whose tail is all repeats"*.
That reasoning is the filtered record's too: the consumer's own code read it
and said no.

## The fix

One assignment on the filtered path, and `sl_accepted`'s comment now reads
"the last index a consumer decided about, in `sl_cb` or in `sc_filter`".
Object mode is unchanged in what it may destroy: `scan_cl_clear()` still lowers
`upto` to `scan_cl_held_first() - 1`.

**The man page needed the wider half of this**, which the comment did not ask
for: `_CLEAR` said it purges "as they are accepted, never ahead of `cb`", and
that is no longer the rule. It now says a record the consumer decided about is
consumed whether `cb` took it or `sc_filter` rejected it, and `sc_filter`'s own
entry says a skipped record counts as consumed for `_CLEAR`. This widens what
clearing may destroy, so it is stated rather than left to be discovered.

`lfs find` is unaffected: `--since` sets `sc_filter` as of this round but never
sets `_CLEAR`.

## Verification

Amended into `20956ec615` -> `4b99909179` (68415), the only commit that touches
the file or the page; the rebase of the six above it was clean. Tip identical
to the reviewed tree, 20 commits and 20 Change-Ids, both changed commits build,
checkpatch unchanged (0 errors, 1 warning, 33 checks — the same counts as
before).

**No lab run**, by the user's call. Clearing needs a registered changelog user,
and the `-u` path fails on any tree without 68413/68414, so a test for it has
to wait until those are in the same tree; the change is code-reviewed and
compile-verified only.
