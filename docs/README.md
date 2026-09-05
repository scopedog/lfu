# LFU documentation index

Four kinds of document live here, and the distinction is the point: the design
documents are **current and maintained**, the dated records — measurements,
review rounds, one-off reviews — are **frozen**, the superseded ones are kept
for provenance, and `local/` is not published at all.

When a measurement contradicts a design document, the design document is
corrected and says so. When a design document is overtaken wholesale, it moves
to `superseded/` with a banner naming what replaced it. Nothing is deleted —
the reason a number changed is often more useful than the number.

## Start here

| Document | What it is |
|---|---|
| [`BOARD.md`](BOARD.md) | **The one page.** Every ticket, every Gerrit id, every patch set and vote in play, the CI state, and what is not ours. Read it before re-deriving any of that |
| [`plan-2.18.md`](plan-2.18.md) | What happens next and in what order |

## The two phases

| | | |
|---|---|---|
| **Phase 1** | userspace design and implementation | Lustre **2.18** |
| **Phase 2** | in-kernel design and implementation | Lustre **2.19** |

Everything on Gerrit today is Phase 1. Phase 2 is the OSD API scanner, the
`circ_buf` kernel→userspace ring, bulk RPC and `OBD_CONNECT2_LFU` — and it sits
behind a wire-format decision that is not ours.

Note that [`design-lfs-find-on-scan.md`](design-lfs-find-on-scan.md) uses
"phase" for the eight stages of the find pipeline, which is a different and
much older use of the word. Where both could be meant, this documentation says
*Phase 1* for the release track and *stage* for the pipeline.

## Design — current, maintained

| Document | What it covers |
|---|---|
| [`architecture.md`](architecture.md) | The whole pipeline: module types, Object Stream, server and client sides, release context |
| [`open-questions.md`](open-questions.md) | Every open and resolved question, by name; the tracking record |
| [`option-comparison.md`](option-comparison.md) | Option 1 (userspace device scanner) vs Option 2 (OSD API), with provenance |
| [`option-1-vs-2.md`](option-1-vs-2.md) | The same comparison as one table, at a glance |
| [`design-common-core.md`](design-common-core.md) | The device-library-free core all backends share |
| [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) | Option 1: libext2fs device scanner |
| [`design-osd-scanner.md`](design-osd-scanner.md) | Option 2: in-kernel OSD API scanner and the ring |
| [`design-zfs-scanner.md`](design-zfs-scanner.md) | The ZFS backend |
| [`design-posix-scanner.md`](design-posix-scanner.md) | The POSIX Input Scanner: the HLD module that turned out to be a contract, not code |
| [`design-changelog-scanner.md`](design-changelog-scanner.md) | The Changelog Input Scanner: an event stream in the Object Stream's record, what the changelog does not carry, the clearing hazard, and where an attribute filter can and cannot be pushed |
| [`design-llapi-scan-device.md`](design-llapi-scan-device.md) | Step 3 upstream: the device scanner behind `llapi_scan_device()`, the plugin, and what the record grows |
| [`design-llapi-scan-fid.md`](design-llapi-scan-fid.md) | `llapi_scan_fid()`: one object by FID, filled the way a walk fills it |
| [`design-lfs-find-on-scan.md`](design-lfs-find-on-scan.md) | LU-20605: how `lfs find`'s deciding half was split out and reused by the device scan, and what that forced into the API |
| [`design-snapshot-scan.md`](design-snapshot-scan.md) | Pointing the shipped userspace scanner at a filesystem *in service*, via `lctl barrier_freeze` + a block snapshot. No kernel change; ldiskfs now, ZFS blocked on the imported-pool question |
| [`filter-levels.md`](filter-levels.md) | The filter vocabulary and its I/O cost tiers |

## Tickets

One document per ticket: the source text as filed, the evidence behind it, and
what is still open. `BOARD.md` has the current patch sets and votes; these have
the reasoning.

| Document | Ticket |
|---|---|
| [`tickets/lu-20462-epic.md`](tickets/lu-20462-epic.md) | **LU-20462**, the epic — status comments for a ticket that is not ours to edit |
| [`tickets/llapi-scan-api.md`](tickets/llapi-scan-api.md) | **LU-20603** · 68094 — the client-side namespace scanner API |
| [`tickets/lfs-find-on-llapi-scan.md`](tickets/lfs-find-on-llapi-scan.md) | **LU-20605** · 68095 — `lfs find` reimplemented on that API, its first consumer |
| [`tickets/llapi-scan-device.md`](tickets/llapi-scan-device.md) | **LU-20606** · 68156 — the ldiskfs device scanner, filed by Dilger |
| [`tickets/lfind.md`](tickets/lfind.md) | **LU-20611** · 68157–68160 — `lfind(8)` and the two refactors it needs |
| [`tickets/zfs-scan-backend.md`](tickets/zfs-scan-backend.md) | **LU-20613** · 68163 — the ZFS backend, and the proof the plugin ABI generalises |
| [`tickets/lma-internal-objects.md`](tickets/lma-internal-objects.md) | **LU-20602** — internal objects and their LMA |
| [`tickets/cb-get-dirstripe-stale-fd.md`](tickets/cb-get-dirstripe-stale-fd.md) | **LU-20624** · 68231 — an upstream stale-fd bug found while building the scanner |
| [`tickets/fid2path-output-format.md`](tickets/fid2path-output-format.md) | **LU-20637** · 68288 — naming a scanned target's objects without asking it |
| [`tickets/lmd-buffer-reuse.md`](tickets/lmd-buffer-reuse.md) | **LU-20643** · 68340 — a reused lmd buffer read as this object's attributes |
| [`tickets/changelog-user-lookup.md`](tickets/changelog-user-lookup.md) | **LU-20647** · 68413 — a registered changelog user cannot be looked up |
| [`tickets/changelog-user-mask.md`](tickets/changelog-user-mask.md) | **LU-20648** · 68414 — `--mask` dropped for a user who has none |
| [`tickets/changelog-scanner.md`](tickets/changelog-scanner.md) | **LU-20649** · 68415 — the Changelog Input Scanner |
| [`tickets/lfs-find-since.md`](tickets/lfs-find-since.md) | **LU-20650** · 68416–68420 — `lfs find --since`, `--changelog`, `--since-cookie` |
| [`tickets/posix-input-scanner.md`](tickets/posix-input-scanner.md) | The POSIX scanner comment on LU-20603, and the statx ticket it points at |

## Review rounds — dated, frozen

[`rounds/`](rounds/) holds one directory per review round: what the reviewers
said, what was verified, what was fixed, what was replied. See
[`rounds/README.md`](rounds/README.md) for the round-by-round index and for the
two things in them that go stale by design.

## Measurements — dated, frozen

Each is a record of one run. They are not edited when later runs disagree; the
later record says what it overturns. Raw logs are under
[`../bench-data/`](../bench-data/).

| Date | Record | Result in one line |
|---|---|---|
| 2026-08-06 | [`throughput-results`](measurements/throughput-results-2026-08-06.md) | Scrub 105k vs device scanner 705k obj/s — the number that started the Option 2 question |
| 2026-08-07 | [`ldiskfs-mdt-parallel`](measurements/ldiskfs-mdt-parallel-2026-08-07.md) | `-j` scaling on a real MDT; output byte-identical across thread counts |
| 2026-08-07 | [`scrub-decomposition`](measurements/scrub-decomposition-2026-08-07.md) | What the 105k proxy was actually measuring |
| 2026-08-07 | [`zfs-mdt-verification`](measurements/zfs-mdt-verification-2026-08-07.md) | The ZFS scanner against a real osd-zfs MDT |
| 2026-08-10 | [`rec-attr-zfs-measured`](measurements/rec-attr-zfs-measured-2026-08-10.md) | `DOIF_ATTR` compiled on ZFS; attributes free on both backends |
| 2026-08-15 | [`parallel-osd-measured`](measurements/parallel-osd-measured-2026-08-15.md) | Private iterators clear 1M obj/s and reverse the ZFS posture |
| 2026-08-16 | [`blockparse`](measurements/blockparse-2026-08-16.md) | `iget` removed from the OSD scan — 10.4× warm |
| 2026-08-16 | [`cold-on-fast-storage`](measurements/cold-on-fast-storage-2026-08-16.md) | A standing cold-scan conclusion retracted |
| 2026-08-17 | [`warm-readahead-and-cold`](measurements/warm-readahead-and-cold-2026-08-17.md) | Readahead costs up to 90% warm; cold, the filter is free |
| 2026-08-17 | [`filter-pushdown-measured`](measurements/filter-pushdown-measured-2026-08-17.md) | The kernel filter built and run; a rejecting tier-0 filter beats no filter |
| 2026-08-17 | [`zfs-tier1-measured`](measurements/zfs-tier1-measured-2026-08-17.md) | Tier 1 on a live ZFS MDT — 14 of 14 agree, tier 1 costs 1.6% |
| 2026-08-17 | [`zfs-suite-regression`](measurements/zfs-suite-regression-2026-08-17.md) | Lustre's own suites against the patched osd-zfs — no regressions |

Two later measurement sets live with their raw data rather than here:
[`../bench-data/2026-09-04/`](../bench-data/2026-09-04/) for what the statx
record costs the device scanner, and
[`../bench-data/2026-09-05/`](../bench-data/2026-09-05/) for the batch API.

## Other dated records

| Document | What it is |
|---|---|
| [`pr186-review.md`](pr186-review.md) | 2026-08-27: the review of Artem's PR 186, the first outside consumer of `llapi_scan_device()` |
| [`maloo-annotate-list.md`](maloo-annotate-list.md) | 2026-08-27: the CI sessions to annotate rather than retest, by failure class |

## Published pages

[`artifacts/`](artifacts/) holds the source of the pages published as Claude
artifacts. **Update these in place — republishing makes a second page with a
new URL.**

| Source | Page |
|---|---|
| [`artifacts/lfu-progress.html`](artifacts/lfu-progress.html) | LFU Phase 1 Progress — the design record against the HLD |
| [`artifacts/llapi-scan-namespace.html`](artifacts/llapi-scan-namespace.html) | `llapi_scan_namespace` — the API guide, including the batch calls |
| [`artifacts/lfs-find-rewrite.html`](artifacts/lfs-find-rewrite.html) | The `lfs find` Rewrite |

## Upstream

| Document | What it covers |
|---|---|
| [`upstream/upstream-survey.md`](upstream/upstream-survey.md) | What already exists in tree vs what LFU must invent |
| [`upstream/xiong-68020-filter-measured-2026-08-17.md`](upstream/xiong-68020-filter-measured-2026-08-17.md) | LU-20591's filter measured against this one |

## Superseded — kept for provenance

Each carries a banner in its own header naming what replaced it. Read them to
find out *why* a conclusion changed, not to find out what is true now.

| Document | Overtaken by |
|---|---|
| [`superseded/throughput-test-plan.md`](superseded/throughput-test-plan.md) | Executed 2026-08-06; its gate premise overtaken 2026-08-15/16 by `DOIF_PARALLEL` and block parsing |
| [`superseded/parallel-osd-scanner-2026-08-15.md`](superseded/parallel-osd-scanner-2026-08-15.md) | Its predictions, by `measurements/parallel-osd-measured-2026-08-15.md` the same day |
| [`superseded/rec-attr-zfs-2026-08-08.md`](superseded/rec-attr-zfs-2026-08-08.md) | Design rationale realized; numbers by `measurements/rec-attr-zfs-measured-2026-08-10.md` |

## Not in this repository

`docs/local/` is gitignored. It holds working material that is not ours to
publish — reviewer correspondence, internal upstream analysis, and the HLD
itself. Documents here may refer to its contents in prose; they do not link to
it. The repository is public: check what a commit publishes before making it.

## Also

- [`reference/`](reference/) — the requirements export and the LUG deck. The HLD is Whamcloud's and is not published here; it lives in `docs/local/`
- [`../bench-data/`](../bench-data/) — raw logs every measurement record links to
- [`../patches/`](../patches/) — the kernel patch stack the OSD work applies
- [`../tests/`](../tests/) — the lab harnesses, `gpoll.py`, and the arm scripts
