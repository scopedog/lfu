# LU-XXXXX: `lfind(8)`, a server-side find over a target scan

**Not yet filed.** Technical task, parent **LU-20462**, related to **LU-20606**
(the scanner it consumes) and **LU-20605** (the front half of the split it
finishes). **Components: utils.**

Design of record: [`design-llapi-scan-device.md`](../design-llapi-scan-device.md) §9.

**Why not under LU-20606.** That ticket's *In scope* is the module — enumeration,
FID recovery, attribute extraction *"driven by a caller-supplied mask"*, filter
pushdown, parallel scan, checkpoint and restart. A command is a caller, not the
module. It is the same split LU-20603 made for the same reason, in its own
words: *"Its own ticket because the scanner has several queued consumers … and
each should be landable on its own."* Two of the four changes here also touch
`lfs` and the namespace side of `liblustreapi`, whose proof is `sanity` 56\* and
has nothing to do with scanning a device.

---

## Summary

utils: lfind, server-side find over a target scan

## Description

**`lfind(8)` is a server-side command, and only that.** It runs on the MDS or
OSS whose disks hold the target, is installed by the server package alone, and
is built under `SERVER` so that a client package does not carry a command with
nothing to read. A Lustre client has no target to read; `lfs find` is the
command there, and stays the way to search a filesystem rather than a target.
The man page, the usage text and the build all say so.

It runs `lfs find`'s predicates against a Lustre target's own objects, read
straight off the device through `llapi_scan_device()` (LU-20606). No mount, no
MDS process and no client: an unmounted target, a snapshot or a failover
partner's LUN is as scannable as a serving one.

It is also **root-only in practice**: reading the device exposes the metadata
of every object on the target with none of the access control a mounted
filesystem applies, which is why it belongs in `sbin` on a server and nowhere
near an unprivileged user.

**Not a mode on `lfs find`.** That command is a client command by
construction, not by convention: `llapi_is_lustre_mnt()` requires `":/"` in the
mount's device name, so a server's target mount is deliberately not recognised
and `lfs find` answers `-ENODEV` on a server with no client mount. A device
scan is disk-reading, root-only, path-less and one target at a time — a
different command, not a flag. `lfs` also ships in `lustre-client` while the
scan backend does not, so the flag would have answered `-ENOTSUP` on every
client install there is. `lfind` installs under `SERVER`, where it can run.

**One vocabulary, not two.** The predicates are not reimplemented: the option
table, its parse loop and the argument helpers move out of `lfs_find()` into a
file compiled into both programs, the way `callvpe.c` already is. Nothing new
is exported and no ABI is touched. A second copy of that table is a copy that
drifts, which is the one thing a replacement for `lfs find` must not do.

**What differs from `lfs find`, and is documented in `lfind(8)`:**
- It prints FIDs. A target holds names and parent FIDs, not paths; `--name`
  matches against every name in the link xattr, and `-printf` is refused.
- One invocation covers one target. Under DNE that is part of a namespace and
  not all of it, and `--local` closes that gap for one node only.
- `--size` and `--blocks` are size-on-MDT's answer or none, because a scan
  cannot glimpse. An object whose size nothing can settle is reported as
  undecided rather than counted as a match or a miss.
- A predicate the target cannot answer — `--ost`, `--mdt`, `--xattr` — is
  refused before the scan starts, since afterwards "no matches" and "could not
  answer" are the same empty output.

**Naming the target:** `--device` always works; `--target NAME` resolves
through `osd-ldiskfs.<name>.mntdev`, which exists only while that target is
mounted here; `--local` takes every target the node serves, skips the MGS
whose llogs are not FID-bearing objects, and reports a target that fails
without ending the sweep, exiting non-zero if any did.

**Acceptance:** the `sanity.sh` 56\* series stays green — it is the whole proof
that moving the parser and splitting `cb_find_init()` changed nothing — and
conf-sanity test_165 diffs `lfind --type f` against what the client saw, on a
stopped filesystem: every regular file must come back and the directory must
not.

**Four changes**, stacked on LU-20606's:

| | Change | Proof |
|---|---|---|
| 1 | `llapi: split the deciding half out of cb_find_init` | `sanity` 56\* |
| 2 | `lfs: share find's predicate parsing` | `sanity` 56\* |
| 3 | `llapi: run find's predicates over a device scan` | conf-sanity test_165 |
| 4 | `utils: lfind, find over a scan of a target` | conf-sanity test_165 |

---

## Two things to settle before filing

**The name.** glibc has `lfind(3)` — a linear-search function on the
`lsearch(3)` page — so `man lfind` finds that one and ours needs `man 8 lfind`.
The prototype, its man page and every document in this project say `lfind`,
which is why it stands; `lfsscan` is the obvious alternative and a reviewer
objecting has a fair point. Filing makes the name public, so decide first.

**A bug to file separately.** The refactor uncovered it: `lfs find` prints its
error and **exits 0** after a bad `--comp-flags` or `--mirror-state`, because
those failures jump to the cleanup without setting `ret`. Change 2 preserves
that behaviour deliberately — fixing it changes what the command returns and
belongs in its own patch against `lfs`.

---

## Paste into Jira (wiki markup)

Jira renders wiki markup, not Markdown: {{{{monospace}}}} replaces backticks,
and a line *starting* with an asterisk becomes a bullet, so a bold lead-in uses
an {{h5.}} heading instead.

```
h5. A server-side command, and only that
{{lfind(8)}} runs on the MDS or OSS whose disks hold the target, is
installed by the server package alone, and is built under SERVER so that a
client package does not carry a command with nothing to read.  A Lustre
client has no target to read: {{lfs find}} is the command there, and stays
the way to search a filesystem rather than a target.  It is root-only in
practice too -- reading the device exposes every object's metadata with
none of the access control a mounted filesystem applies.

It runs {{lfs find}}'s predicates against a Lustre target's own objects,
read straight off the device through {{llapi_scan_device()}} (LU-20606).
No mount, no MDS process and no client: an unmounted target, a snapshot or
a failover partner's LUN is as scannable as a serving one.

h5. Not a mode on lfs find
That command is a client command by construction, not by convention:
{{llapi_is_lustre_mnt()}} requires ":/" in the mount's device name, so a
server's target mount is deliberately not recognised and {{lfs find}}
answers -ENODEV on a server with no client mount.  A device scan is
disk-reading, root-only, path-less and one target at a time -- a different
command, not a flag.  {{lfs}} also ships in lustre-client while the scan
backend does not, so the flag would have answered -ENOTSUP on every client
install there is.  {{lfind}} installs under SERVER, where it can run.

h5. One vocabulary, not two
The predicates are not reimplemented: the option table, its parse loop and
the argument helpers move out of {{lfs_find()}} into a file compiled into
both programs, the way {{callvpe.c}} already is.  Nothing new is exported
and no ABI is touched.  A second copy of that table is a copy that drifts,
which is the one thing a replacement for {{lfs find}} must not do.

h5. What differs from lfs find
- It prints FIDs.  A target holds names and parent FIDs, not paths;
{{--name}} matches against every name in the link xattr, and {{-printf}} is
refused.
- One invocation covers one target.  Under DNE that is part of a namespace
and not all of it, and {{--local}} closes that gap for one node only.
- {{--size}} and {{--blocks}} are size-on-MDT's answer or none, because a
scan cannot glimpse.  An object whose size nothing can settle is reported
as undecided rather than counted as a match or a miss.
- A predicate the target cannot answer -- {{--ost}}, {{--mdt}}, {{--xattr}}
-- is refused before the scan starts, since afterwards "no matches" and
"could not answer" are the same empty output.

h5. Naming the target
{{--device}} always works; {{--target NAME}} resolves through
{{osd-ldiskfs.<name>.mntdev}}, which exists only while that target is
mounted here; {{--local}} takes every target the node serves, skips the MGS
whose llogs are not FID-bearing objects, and reports a target that fails
without ending the sweep, exiting non-zero if any did.

h5. Acceptance
The {{sanity.sh}} 56* series stays green -- it is the whole proof that
moving the parser and splitting {{cb_find_init()}} changed nothing -- and
conf-sanity test_165 diffs {{lfind --type f}} against what the client saw,
on a stopped filesystem: every regular file must come back and the
directory must not.
```
