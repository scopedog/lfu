# Queued for the next patchset (round 11)

Findings since the 2026-08-26 push that are **not** in what is on Gerrit.
Do not push for these alone — batch them with whatever this round's CI
returns. One patchset per review cycle.

`round11-code.patch` applies to `lu-20650-since` (`e0265228c5`, the
`--changelog` commit), and is also parked as `stash@{0}` in
`~/projects/lustre/lustre-scanfid`.

| Change | Finding | Verdict |
|---|---|---|
| 68418 | `liblustreapi_pfind.c:3558` is 82 columns — a tab counts as 8 | **real**, fixed in the patch |
| 68417 | `'time_t' may be misspelled - perhaps 'timeout_t'?` | **noise** — `time_t` already appears 6 times in that header (`fp_atime`, `fp_mtime`, `fp_ctime`, `fp_newery`); it is the file's own convention |
| 68288 | Maloo `review-dne-subtest-change` failed | **no action** — on PS2, superseded by PS3. A failure on a superseded patchset needs none |

Also outstanding, not a code fix: Gerrit warns *"subject >50 characters"* on
most of the series. It is a warning and the commit-msg hook's own limit is 62,
but it is a house preference worth honouring when the messages are next
touched.
