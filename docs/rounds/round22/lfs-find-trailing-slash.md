# `-name` and a trailing-slash start point — 2026-09-06

68095 `937bc492`, followed to the end. The reviewer's claim was *"a
behaviour delta the message does not list"*, and that is exactly what it is:
**not a regression, and not an improvement** — different wrong answers.

## Measured against stock, which is the comparison that settled it

Stock `lfs` built from this series' base `5afbab284e` (`2.17.57_43_g5afbab2`)
on the lab, run beside ours and GNU find on one fixture.

**Path printing is byte-identical between stock and ours** at every start
point tested, including `/` and three trailing slashes. The doubled
separator comes from an unconditional `strcat(path, "/")` in
`llapi_semantic_traverse()` that predates the series — **not ours**, and
held as a ticket to file later.

**`-name`, trailing-slash start point:**

| pattern | GNU find | stock | ours (before) | ours (after) |
|---|---|---|---|---|
| `slashdir` | match | no | no | **match** |
| `*slashdir*` | match | no | match | **match** |
| `*/` | no | no | match | **no** |
| score vs find(1) | — | 1/3 | 1/3 | **3/3** |

Stock matches *nothing*, its `fname` being `""`. So 68095 traded a false
negative for a false positive; the score is unchanged. That is worth saying
plainly, because "the record broke `-name`" would have been wrong.

## Why the fix is three lines and not an API change

I first reasoned this was a `sr_name` contract question. It is not.
`scan_rec_dirent()`'s own comment already says `basename(3)`, and **two of
the three entry points honour it** by trimming the path first —
`llapi_scan_namespace()` and `llapi_scan_fid()`. Measured:

    llapi_scan_namespace("/mnt/lustre/")     sr_name="lustre"
    llapi_scan_namespace("/mnt/lustre///")   sr_name="lustre"
    llapi_scan_namespace("/")                sr_name="/"

`llapi_find()` was the one that did not. The trim goes there, into a local
buffer — the caller's is `argv` in `lfs(1)`, and both `param_callback()` and
`pfind_param_callback()` copy what they are given.

The reason it cannot be fixed inside `scan_rec_dirent()`: `sr_name` must
point **into** `sr_path` — the header says so, `llapi_scan_test.c:696`
asserts it, and the batch layer reproduces it as an offset. For
`/mnt/lustre/` no suffix pointer spells `lustre`.

## What the trim buys, and what it costs

| | `-name` | child lines | start-point line |
|---|---|---|---|
| stock / ours before | 1/3 | doubled separator | matches find(1) |
| ours after | **3/3** | **matches find(1)** | trimmed, differs |

One cosmetic line traded for a correct predicate and correct child paths.
`find(1)` echoes the spelling it was given; closing that last gap needs the
separator fix, which is the upstream ticket.

## Arms

`tests/lab-r18/08-arms-slash.sh` — thirteen assertions over the three
spellings plus `/`, with a no-trailing-slash control that must pass either
way. **Validated against the stock build: 6 pass / 7 fail there, 13 / 0
with the trim.**

Regression check on the same build: r21 arms **17/0**, r19 cookie arms
**8/0**, `--projid 0` / `! --projid 0` and `STATX_INO` unchanged, and
`sanity` 56El, 157c, 160aa–160ad **PASS x2, zero skips**.

checkpatch: 0 errors, 1 warning — a spell-check false positive on `strcat`.

## On Gerrit

A correction is posted on `937bc492`: my first reply called it a
record-contract change and did not say it was not a regression. Both now
stated, with the stock numbers. Thread left open, since the patch that
answers it is not pushed yet.
