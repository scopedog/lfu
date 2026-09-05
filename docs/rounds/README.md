# Review rounds — dated, frozen

One directory per review round: what the reviewers said, what was verified,
what was fixed, and what was replied. **These are records, not maintained
documents.** They are not edited when a later round disagrees — the later
round says what it overturns, exactly as `../measurements/` does.

So a claim here is true *as of its round*. Two in particular go stale by
design and are left alone: whether something was pushed (rounds up to 21 are
all on Gerrit now) and what the scan record's fields were called (the statx
switch of 2026-09-04 moved eleven of them into `sr_stx`).

A round numbered `-pending` is one whose queued work was written down before
the push it was waiting for. The name is kept because other documents cite the
path.

| Round | Date | What it holds |
|---|---|---|
| [`round10-pending`](round10-pending/) | 2026-08-25 | Six round-9 points deliberately left unresolved on Gerrit until the next push, with the code patch and three commit messages |
| [`round11-pending`](round11-pending/) | 2026-08-26 | Findings after the push that were not yet on Gerrit, batched rather than pushed alone; includes the fetch instructions owed to Artem |
| [`round11-lab-scope.md`](round11-lab-scope.md) | 2026-08-27 | What the round-11 lab did and did not cover |
| [`round14-pending`](round14-pending/) | 2026-08-29 | The replies to post after that round's push |
| [`round15`](round15/) | 2026-08-30 | Triage and reply drafts. Its `sanity-hsm` failure logs moved to [`bench-data/2026-08-30-hsm254b/`](../../bench-data/2026-08-30-hsm254b/) |
| [`round16`](round16/) | 2026-08-31 | The lab record on `lab-r16`, triage, replies, and Artem's fetch line |
| [`round17`](round17/) | 2026-09-01 | The 45-comment AI sweep across 13 changes — raw JSON, the reply drafts, and the repro scripts |
| [`round18`](round18/) | 2026-09-02 | The AI review on 68094 PS15, and the offline `--fid2path` work (LU-20637) |
| [`round19`](round19/) | 2026-09-03 | The five defects the sweep found, and the reply pass over the open AI threads |
| [`round20`](round20/) | 2026-09-04 | The largest round: the `56El` root cause, adilger's first review, twelve `lreview` runs, and the statx record — scoped, chosen, ported down the series and costed |
| [`round21`](round21/) | 2026-09-04 | The Gerrit AI backlog answered — 103 of 113 threads, and why ten were left open |
| [`round22`](round22/) | 2026-09-05 | `lreview` on the batch API and on 68094 PS17, and the unposted reply to adilger about bulk records |

## The pattern these records show

Worth knowing before reading any single one:

- **The AI reviewers repeat themselves across patch sets.** The same point
  arrives again on the next revision, so a round's value is its *triage* —
  which findings were real, which were already fixed, which were noise.
- **`lreview` has a better hit rate than the Gerrit AI**, and the difference
  is that it reviews before the push:
  [`round20/lreview-complete.md`](round20/lreview-complete.md) is the twelve-run
  record, and [`round22/`](round22/) the two runs since.
- **Verify the reviewer, not just the code.** Round 20 has two findings that
  were right about the code and wrong about the consequence, and one the
  reviewer understated.
