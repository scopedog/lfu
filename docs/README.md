# LFU documentation index

Four kinds of document live here, and the distinction is the point: the design
documents are **current and maintained**, the measurement records are **dated
and frozen**, the superseded ones are kept for provenance, and `local/` is not
published at all.

When a measurement contradicts a design document, the design document is
corrected and says so. When a design document is overtaken wholesale, it moves
to `superseded/` with a banner naming what replaced it. Nothing is deleted —
the reason a number changed is often more useful than the number.

## Design — current, maintained

| Document | What it covers |
|---|---|
| [`plan-2.18.md`](plan-2.18.md) | What happens next and in what order, under the 2.18 userspace / 2.19 kernel split |
| [`architecture.md`](architecture.md) | The whole pipeline: module types, Object Stream, server and client sides, release context |
| [`open-questions.md`](open-questions.md) | Every open and resolved question, by name; the tracking record |
| [`option-comparison.md`](option-comparison.md) | Option 1 (userspace device scanner) vs Option 2 (OSD API), with provenance |
| [`option-1-vs-2.md`](option-1-vs-2.md) | The same comparison as one table, at a glance |
| [`design-common-core.md`](design-common-core.md) | The device-library-free core all backends share |
| [`design-ldiskfs-scanner.md`](design-ldiskfs-scanner.md) | Option 1: libext2fs device scanner |
| [`design-osd-scanner.md`](design-osd-scanner.md) | Option 2: in-kernel OSD API scanner and the ring |
| [`design-zfs-scanner.md`](design-zfs-scanner.md) | The ZFS backend |
| [`filter-levels.md`](filter-levels.md) | The filter vocabulary and its I/O cost tiers |
| [`design-lfs-find-on-scan.md`](design-lfs-find-on-scan.md) | LU-20605: how `lfs find` splits onto the scanner API, and what that forced into the API |
| [`design-llapi-scan-device.md`](design-llapi-scan-device.md) | Step 3 upstream: the device scanner behind `llapi_scan_device()`, the plugin, and what the record grows |

## Measurements — dated, frozen

Each is a record of one run. They are not edited when later runs disagree; the
later record says what it overturns.

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

## Upstream

| Document | What it covers |
|---|---|
| [`upstream/upstream-survey.md`](upstream/upstream-survey.md) | What already exists in tree vs what LFU must invent |
| [`upstream/xiong-68020-filter-measured-2026-08-17.md`](upstream/xiong-68020-filter-measured-2026-08-17.md) | LU-20591's filter measured against this one |

## Tickets

| Document | State |
|---|---|
| [`tickets/lma-internal-objects.md`](tickets/lma-internal-objects.md) | **Filed as LU-20602.** Source text, evidence, and what is still open |
| [`tickets/llapi-scan-api.md`](tickets/llapi-scan-api.md) | **LU-20603, Gerrit 68094.** Client-side namespace scanner API — the reusable half of LU-20462's first step |
| [`tickets/lfs-find-on-llapi-scan.md`](tickets/lfs-find-on-llapi-scan.md) | **LU-20605, Gerrit 68095.** `lfs find` reimplemented on that API — its first consumer |
| [`tickets/llapi-scan-device.md`](tickets/llapi-scan-device.md) | **LU-20606**, filed by Dilger; written and tested. The ldiskfs device scanner behind `llapi_scan_device()` — step 3 |
| [`tickets/lfind.md`](tickets/lfind.md) | **LU-20611.** `lfind(8)`, the scanner's first consumer, and the two refactors it needs |

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
publish — reviewer correspondence and internal upstream analysis. Documents
here may refer to its contents in prose; they do not link to it.

## Also

- [`reference/`](reference/) — the HLD, the requirements export, and the LUG deck
- [`../bench-data/`](../bench-data/) — raw logs every measurement record links to
- [`../patches/`](../patches/) — the kernel patch stack the OSD work applies
