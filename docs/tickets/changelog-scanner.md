# LU-20649 — the Changelog Input Scanner

**Status:** filed as LU-20649 on 2026-08-26. The commit is `38e691a616` on
branch `lu-20649-changelog-scan` in `~/projects/lustre/lustre-lu20649`, sitting
on top of the rebuilt round-10 stack. Change-Id
`I12efd3bd2150592a4507533129ab56573ef924d9`. checkpatch: 0 errors, 1 warning
(the MAINTAINERS question every new file gets). **Not yet pushed, and it cannot
go before round 10** — it is the tenth patch of the series.

**Jira:** [LU-20649](https://jira.whamcloud.com/browse/LU-20649) ·
**Type:** Technical task (as LU-20603, LU-20605, LU-20611, LU-20613 are) ·
**Epic:** LU-20462 · **Component:** none (the LU project defines none)

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim;
do not reflow it. Rules are in `changelog-user-lookup.md`.

---

## Summary (as filed)

```
llapi: read an MDT changelog as a stream of scan records
```

## Description (paste verbatim into Jira)

LFU's two scanners enumerate what *exists*: a namespace walk (LU-20603) and a
target scan (LU-20606, LU-20613). A changelog enumerates what *happened*.
Delivering it in the same {{struct llapi_scan_rec}} means a consumer written
against either can be fed by a delta without being rewritten.

This is the library half only.
{{lfs find --since}} and {{lfs find --changelog}} are a separate change.

h3. The interface

New {{lustre/utils/liblustreapi_scan_changelog.c}}, one exported call:

{noformat}
	int llapi_scan_changelog(const struct llapi_scan_changelog_param *sc,
				 llapi_scan_cb_t cb, void *data);

	LLAPI_SCAN_CL_F_FOLLOW    /* wait at the end of the log */
	LLAPI_SCAN_CL_F_COALESCE  /* one record per object, not per event */
	LLAPI_SCAN_CL_F_RESOLVE   /* fill what the log lacks */
	LLAPI_SCAN_CL_F_CLEAR     /* destructive; off by default */
{noformat}

The parameter block is versioned by {{sc_size}} like the other scanners', and
names the MDT, the registered user, a record range, a type mask and a demand
mask.

h3. What it answers for

A record carries the FID, the parent FID, the name, the event and its time,
and, where the server recorded them, the uid and gid. Size, mode, times,
layout and HSM state are not in a changelog at any setting, so they arrive
absent with their {{sr_valid}} bit clear rather than as zeroes.
{{LLAPI_SCAN_CL_F_RESOLVE}} fills them through a client mount, one open and
one stat each, and the demand mask decides whether that happens at all.
Resolution fills what the stream lacks and never restates what it has, so a
caller can ask what an event recorded rather than what is true now.

The record gains {{sr_event_type}}, {{_flags}}, {{_time}}, {{_index}} and
{{_prev}}, the rename source and a job id, behind three new validity bits. An
event time is not an object time, so it does not land in {{sr_mtime}}.

Object mode holds events in a FID-keyed cache and delivers one record per
object once it has been quiet, so a file written a hundred times is one record
and one lookup rather than a hundred of each.

Clearing is off by default and never runs ahead of the callback: it is
irreversible and purges the registered user's whole backlog, not this reader's
alone. Registering that user stays the caller's, since registering without
consuming is how an MDT fills up.

h3. What ran

First run against a real changelog, single-node lab, 2026-08-25:

{noformat}
	99 records delivered, 97 with a FID, 48 with a name
	99 events coalesce to 45 objects
	0 objects resolved when unasked, 69 of 99 when asked
	an early stop returns the consumer's own value
	seven malformed parameter blocks refused with -EINVAL
{noformat}

The two records without a FID are the rename pair, whose {{cr_tfid}} is zero.

Also adds {{Documentation/man3/llapi_scan_changelog.3}} and
{{lustre/tests/llapi_scan_changelog_test.c}}, the program that produced those
numbers.

---

## Notes for us, not for the ticket

### The round-10 fixes were folded in, and are now out — done

The old `lu-changelog-scan` commit touched six files that are **not** part of
the changelog scanner: `llapi_scan_namespace.3`, `lfs_find_parse.c/.h`,
`liblustreapi_pfind.c`, `liblustreapi_scan_device.c` and `libscan_ldiskfs.c`.
Their changed lines were byte-identical to
`docs/round10-pending/round10-code.patch`.

`38e691a616` is the same work rebuilt on top of the round-10 stack with those
six dropped, so they are carried by their proper parent commits instead. The
check that it is right: `git diff lu-changelog-scan 38e691a616` is **empty** —
the resulting tree is identical, which is only possible if the dropped files
were exactly the ones the parents already carry.

`lu-changelog-scan` is left in place as the backup.

### The man page `.TH` line is 82 columns, and that is fine

`checkpatch-man.pl` reports `CHECK: Line length of 82 exceeds 80 columns` for
`llapi_scan_changelog.3`, as it does for `llapi_scan_namespace.3`. It is the
standard `.TH NAME 3 DATE "Lustre User API" "Lustre Library Functions"` that 88
of the 145 pages in `Documentation/man3/` use, and **60 of them are already
over 80 columns**. Shortening ours would break with the convention to satisfy a
CHECK the tree ignores. Left alone deliberately.

### It is not the last piece

`lfs find --since` and `lfs find --changelog` are steps 4–5 of
`docs/design-changelog-scanner.md` and are a separate change. `--since` needs
`llapi_scan_fid()` first, so that verification fills a record the same way the
walk does; without it, `--since -stripe-count 4` would answer differently from
a plain find on the same filesystem.

`llapi_scan_changelog_test` exists but no `sanity` or `conf-sanity` case runs
it yet. A reviewer will ask.

### Two upstream bugs came out of building it

Both filed, both fixed and unpushed: **LU-20647** (a plainly registered
changelog user cannot be looked up) and **LU-20648** (`--mask` dropped for a
user who has none). Neither is caused by this work; the scanner reaches the
changelog through the same ioctl and hit them first.
