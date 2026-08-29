# POSIX Input Scanner — an LU-20603 comment, and one follow-up ticket

**Decided 2026-08-29: no new ticket for the module.** LU-20603 is
`llapi_scan_namespace()`, and the POSIX Input Scanner *is*
`llapi_scan_namespace()` — the HLD draws them as two boxes, but in the tree
there is one function, one traversal and one record, and the fix has to land in
68094 rather than in a change of its own. A ticket owning no change is
bookkeeping a maintainer reads past.

**The one condition that would change it:** if module completion is reported by
counting subtasks of LU-20462, a comment on LU-20603 does not appear in that
audit, and the subtask earns its keep. Then file A from the git history of this
file (commit `6447aaa`).

So: **A is now a comment to post on LU-20603**, and **B stays a ticket draft**,
Technical task, parent LU-20462, to file only when the follow-up is wanted.

Background: [`design-posix-scanner.md`](../design-posix-scanner.md), lab
[`tests/lab-posix/`](../../tests/lab-posix/).

---

# A. Comment to post on LU-20603

No summary line, no fields: it is a comment on the existing ticket. Same
formatting rule as a description, written without double hyphens, asterisks or
braces in the prose so Jira's editor has nothing to autoformat.

---

This ticket also delivers the High Level Design's POSIX Input Scanner module,
which is why no separate ticket exists for it.

The High Level Design asks for a POSIX Input Scanner beside the Lustre
namespace scanner, so that the same searches work over storage that is not
Lustre. It names the consumers as Client Side File Cache (PCC-RO) and Trash Can
Undelete (TCU), and it asks for the module to be implemented inside the
namespace scanner rather than as a duplicate parallel scanner.

That is not a scanner to write. The namespace walk has fetched attributes with

```
ioctl(LL_IOC_MDC_GETINFO_V2)
```

and fallen back to a stat when that answers

```
ENOTTY
```

since long before this work, so a search already crosses onto a filesystem that
is not Lustre and answers there. Measured on a lab: `lfs find` answers `-type`,
`-size`, `-mtime` and `-uid` correctly on an ext4 tree today.

What was missing is not traversal but the record's honesty. A scan record
carries a validity mask saying which fields the scanner could answer for, and
off Lustre that mask was wrong about one field.

Every regular file scanned outside Lustre came back with

```
LLAPI_SCAN_FID
```

set, and a FID built out of the object's own filename:

```
/tmp/ptree/a      fid=[0x61:0x0:0x0]
/tmp/ptree/big    fid=[0x676962:0x0:0x0]
```

`0x61` is the letter a. `0x676962` is the string big. The walk writes the
object name into the attribute buffer because that buffer is the ioctl input as
well as its output; the ioctl fails with ENOTTY; the stat fallback fills the
statx fields and never touches the FID; and

```
fid_is_sane()
```

reads the leftover name bytes as a valid IGIF. An IGIF is a legitimate FID
shape, so nothing downstream could catch it. A consumer doing exactly what the
validity mask promises would read a fabricated FID and, for example, ask an MDT
about it.

This ticket covers stating the contract for a target that is not Lustre and
enforcing it:

A record gathered from a stat carries type, mode, link count, owner, size,
blocks and the three timestamps, plus the project id on demand where the
filesystem supports project quotas.

It carries none of the fields only Lustre has. The FID, the layout, the
directory stripe, the MDT index and the HSM state all leave their bits clear
rather than reading as zero or as something invented.

Nothing about the traversal, the thread pool, the demand mask or the predicates
changes. The POSIX Input Scanner is the namespace scanner with a different
attribute source, which is what the design asks for.

## Acceptance

A new case in `llapi_scan_test` builds a tree on a filesystem that is not
Lustre, scans it through `llapi_scan_namespace()`, and asserts both halves:
that what a stat answers is present, and that the FID, layout, directory
stripe, MDT index and HSM bits are all clear.

The case refuses to run on Lustre rather than pass there, because every absence
it asserts would be present for a good reason on Lustre and a green run would
mean nothing. sanity test_157c passes it a directory outside the filesystem
under test.

```
test10: a record off Lustre carries what a stat answers, and no FID   pass
PASS 157c
```

Verified against a build with the fix removed, where the same case fails:

```
a record off Lustre carried a FID: valid=0x43ff
```

## Why it is in this ticket and not its own

The POSIX Input Scanner is this module with a different attribute source, so
there is no second scanner to track. The fix also has to be here: this call is
the first consumer of the FID field for an object the ioctl did not answer for,
so it is what turns a latent stale value into a published one, and landing the
API under one ticket with the fix under another would ship a release that
reports invented FIDs.

Nothing upstream reads that field for such an object today. `lfs find -printf`
resolves a FID from the pathname instead, which is why this is not an upstream
defect report.

---

# B. The follow-up, still a ticket if you want it tracked

## Summary line

```
LFU: fetch attributes with statx for filesystems that are not Lustre
```

## Description, paste-ready

---

The attribute fallback for an object that is not on Lustre uses a stat, which
cannot report a birth time or the statx attribute flags. So a record gathered
outside Lustre leaves

```
LLAPI_SCAN_BTIME
LLAPI_SCAN_ATTRS
```

clear, and `lfs find -btime` matches nothing there. Fetching with

```
statx()
```

would answer both on a filesystem that has them, such as ext4 or XFS.

This is an enhancement and not a defect, for two reasons worth recording so
that it is not filed twice as a bug.

The High Level Design does not require it. It suggests statx as a likely
implementation route for the POSIX Input Scanner, in a sentence whose
requirement is that the module be built inside the namespace scanner rather
than duplicated. The module itself sits outside the three initial Input
Scanners the design names. A birth time is not in the standard attribute list
it asks for, which is size, blocks, atime, mtime and ctime. And it states that
attributes should be returned if readily available and omitted if not, which is
what the validity mask already does.

The behaviour is also already deliberate and is not specific to POSIX. An
object with no birth time does not match a birth time test, and the search
carries on rather than failing, because failing after matches have been printed
is the wrong answer and on a walk the error would take the whole subtree with
it. An old ldiskfs inode whose

```
i_extra_isize
```

does not reach

```
i_crtime
```

has no birth time either and behaves the same way on Lustre. Fetching with
statx would fix that for the POSIX case and leave the ldiskfs case as it is, so
it moves the boundary rather than removing it.

## Acceptance

A scan of a tree on ext4 reports a birth time, and `lfs find -btime` answers
there as it does on Lustre. A filesystem with no birth time, such as tmpfs,
still leaves the bit clear and still does not match, which the existing case
already asserts.
