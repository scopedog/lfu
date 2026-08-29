# POSIX Input Scanner — the LU-20603 comment, and the statx ticket

**A is posted.** The comment went on
[LU-20603](https://jira.whamcloud.com/browse/LU-20603) on 2026-08-29, so the
module is recorded where its code lives and no separate ticket exists for it.
Kept below as the record of what was said.

**B is being filed** as a Technical task, parent LU-20462. When it has a
number, put it here and in the commit subject of the patch that writes it.

Why the split: LU-20603 is `llapi_scan_namespace()` and the POSIX Input
Scanner *is* `llapi_scan_namespace()` — two boxes in the HLD diagram, one
function in the tree — while statx is a separate change to a separate
behaviour. The one condition that would have made A its own ticket, and did
not apply: module completion reported by counting subtasks of LU-20462, which
a comment does not appear in. The standalone draft is in this file's history
at `6447aaa`.

**Markup:** `jira.whamcloud.com` is Jira Server 9.12 and takes wiki markup, not
Markdown — `{noformat}` blocks, `{{inline}}`, and every identifier in braces
because a matched pair of underscores italicises. See [[jira-wiki-markup]] in
memory, and LU-20637, whose description still shows the raw backticks from
before we knew.

Background: [`design-posix-scanner.md`](../design-posix-scanner.md), lab
[`tests/lab-posix/`](../../tests/lab-posix/).

---

# A. Posted on LU-20603, 2026-08-29

As posted:

---

This ticket also delivers the High Level Design's POSIX Input Scanner module,
so there is no separate ticket for it. The design asks for that module to be
built inside the namespace scanner rather than duplicated, and it is this
scanner with a stat as the attribute source: the walk has fallen back to a stat
when the attribute ioctl answers {{ENOTTY}} since long before this work, so a
search already crossed onto storage that is not Lustre and answered there.

What was missing was the record's honesty. Off Lustre every regular file came
back with {{LLAPI_SCAN_FID}} set and a FID built out of its own filename:

{noformat}
/tmp/ptree/a      fid=[0x61:0x0:0x0]
/tmp/ptree/big    fid=[0x676962:0x0:0x0]
{noformat}

0x61 is the letter a and 0x676962 is the string big. The walk writes the name
into the attribute buffer because that buffer is the ioctl input as well as its
output, the ioctl then fails, the stat fallback never touches the FID, and
{{fid_is_sane()}} reads the leftover bytes as a valid IGIF. That is a
legitimate FID shape, so nothing downstream could catch it.

The contract is now stated and enforced. A record gathered from a stat carries
type, mode, link count, owner, size, blocks and the three timestamps, plus the
project id on demand. The FID, the layout, the directory stripe, the MDT index
and the HSM state leave their bits clear.

{{llapi_scan_test}} gained a case that scans a tree outside Lustre and asserts
both halves, and it refuses to run on Lustre, where every absence it checks
would be present for a good reason. sanity 157c passes it a directory outside
the filesystem under test. Against a build with the fix removed it fails:

{noformat}
a record off Lustre carried a FID: valid=0x43ff
{noformat}

---

# B. Being filed — LU-?????

## Summary line

The Summary field is plain text, not wiki markup, so this goes in as it reads:

> LFU: fetch attributes with statx for filesystems that are not Lustre

## Description, paste-ready

Same markup as A.

---

The attribute fallback for an object that is not on Lustre uses a stat, which
cannot report a birth time or the statx attribute flags. So a record gathered
outside Lustre leaves {{LLAPI_SCAN_BTIME}} and {{LLAPI_SCAN_ATTRS}}
clear, and {{lfs find -btime}} matches nothing there. Fetching with {{statx()}}
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
it. An old ldiskfs inode whose {{i_extra_isize}} does not
reach {{i_crtime}} has no birth time either and behaves the same way on Lustre. Fetching with
statx would fix that for the POSIX case and leave the ldiskfs case as it is, so
it moves the boundary rather than removing it.

## Acceptance

A scan of a tree on ext4 reports a birth time, and {{lfs find -btime}} answers
there as it does on Lustre. A filesystem with no birth time, such as tmpfs,
still leaves the bit clear and still does not match, which the existing case
already asserts.
